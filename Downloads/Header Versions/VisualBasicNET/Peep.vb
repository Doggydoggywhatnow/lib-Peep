' Liberated Peep for Visual Basic .NET (P/Invoke)
Imports System
Imports System.IO
Imports System.Reflection
Imports System.Runtime.InteropServices

Namespace LiberatedPeep

    ''' <summary>Decodes a WAV or FLAC file held in memory into stereo 16-bit samples.</summary>
    Public NotInheritable Class Peep
        Implements IDisposable

        Private NotInheritable Class Native
            <DllImport("peep")> Public Shared Function peep_open(p As IntPtr, codecs As IntPtr, data As IntPtr, len As UIntPtr, work As IntPtr, workSize As UIntPtr) As Integer
            End Function
            <DllImport("peep")> Public Shared Function peep_fill(p As IntPtr, outBuf As IntPtr, frames As UIntPtr) As UIntPtr
            End Function
            <DllImport("peep")> Public Shared Sub peep_seek(p As IntPtr, frame As ULong)
            End Sub
            <DllImport("peep")> Public Shared Sub peep_close(p As IntPtr)
            End Sub
            <DllImport("peep")> Public Shared Function peep_flac() As IntPtr   ' address of the FLAC codec table
            End Function

            Shared Sub New()
                NativeLibrary.SetDllImportResolver(GetType(Native).Assembly, AddressOf Resolve)
            End Sub

            Private Shared Function Resolve(name As String, asm As Assembly, path As DllImportSearchPath?) As IntPtr
                If name <> "peep" Then Return IntPtr.Zero
                Dim file As String = If(RuntimeInformation.IsOSPlatform(OSPlatform.Windows), "peep.dll", "libpeep.so")
                For Each c As String In New String() {Environment.GetEnvironmentVariable("PEEP_LIB"),
                                                      System.IO.Path.Combine(Directory.GetCurrentDirectory(), file),
                                                      System.IO.Path.Combine(AppContext.BaseDirectory, file)}
                    If Not String.IsNullOrEmpty(c) AndAlso System.IO.File.Exists(c) Then Return NativeLibrary.Load(c)
                Next
                Throw New DllNotFoundException("libpeep not found: run ./build.sh first (or set PEEP_LIB)")
            End Function
        End Class

        Private ReadOnly _p, _data, _codecs, _out As IntPtr
        Private _work As IntPtr

        ''' <param name="bytes">a WAV or FLAC file</param>
        Public Sub New(bytes As Byte())
            _data = Marshal.AllocHGlobal(bytes.Length)              ' the library reads from this: keep it alive
            Marshal.Copy(bytes, 0, _data, bytes.Length)
            _p = Zeroed(160)                                        ' struct peep
            _codecs = Zeroed(16)
            Marshal.WriteInt64(_codecs, 0, Native.peep_flac().ToInt64())
            If Native.peep_open(_p, _codecs, _data, New UIntPtr(CULng(bytes.Length)), IntPtr.Zero, UIntPtr.Zero) = 0 Then
                Dim need As Long = Marshal.ReadInt64(_p, 144)       ' work_need
                If need = 0 Then Throw New ArgumentException("not a playable WAV or FLAC file")
                _work = Zeroed(CInt(need))
                If Native.peep_open(_p, _codecs, _data, New UIntPtr(CULng(bytes.Length)), _work, New UIntPtr(CULng(need))) = 0 Then
                    Throw New ArgumentException("not a playable WAV or FLAC file")
                End If
            End If
            _out = Zeroed(4096 * 4)
        End Sub

        Private Shared Function Zeroed(n As Integer) As IntPtr
            Dim m As IntPtr = Marshal.AllocHGlobal(n)
            Marshal.Copy(New Byte(n - 1) {}, 0, m, n)
            Return m
        End Function

        Public ReadOnly Property Rate As UInteger          ' Hz
            Get
                Return CUInt(Marshal.ReadInt32(_p, 40) And &HFFFFFFFFL)
            End Get
        End Property
        Public ReadOnly Property Channels As UInteger      ' channels in the file
            Get
                Return CUInt(Marshal.ReadInt32(_p, 44) And &HFFFFFFFFL)
            End Get
        End Property
        Public ReadOnly Property Total As Long             ' frames, 0 = unknown
            Get
                Return Marshal.ReadInt64(_p, 32)
            End Get
        End Property
        Public ReadOnly Property Position As Long          ' frames played so far
            Get
                Return Marshal.ReadInt64(_p, 24)
            End Get
        End Property

        ''' <summary>Up to <paramref name="frames"/> stereo frames as interleaved samples; empty at the end.</summary>
        Public Function Read(Optional frames As Integer = 1024) As Short()
            Dim n As Integer = CInt(Native.peep_fill(_p, _out, New UIntPtr(CULng(Math.Min(frames, 4096)))).ToUInt64())
            Dim s(n * 2 - 1) As Short
            If n > 0 Then Marshal.Copy(_out, s, 0, s.Length)
            Return s
        End Function

        Public Sub Seek(frame As ULong)
            Native.peep_seek(_p, frame)
        End Sub

        ''' <summary>Volume 0..256 (256 = full).</summary>
        Public Sub SetGain(q8 As Integer)
            Marshal.WriteInt32(_p, 48, Math.Max(0, Math.Min(256, q8)))
        End Sub

        Public Sub Dispose() Implements IDisposable.Dispose
            Native.peep_close(_p)
            Marshal.FreeHGlobal(_p) : Marshal.FreeHGlobal(_data) : Marshal.FreeHGlobal(_codecs) : Marshal.FreeHGlobal(_out)
            If _work <> IntPtr.Zero Then Marshal.FreeHGlobal(_work)
        End Sub
    End Class

End Namespace
