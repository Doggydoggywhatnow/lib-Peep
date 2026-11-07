Imports System
Imports System.IO
Imports LiberatedPeep

Module Program
    Sub Main()
        For Each name As String In New String() {"test.wav", "test.flac"}
            Using peep As New Peep(File.ReadAllBytes(Path.Combine(Directory.GetCurrentDirectory(), name)))
                Dim total As Long = 0, sum As Long = 0
                Do
                    Dim s As Short() = peep.Read(1024)
                    If s.Length = 0 Then Exit Do
                    total += s.Length \ 2
                    For Each v As Short In s
                        sum += v
                    Next
                Loop
                peep.Seek(2205UL)
                Dim seekSum As Long = 0
                For Each v As Short In peep.Read(100)
                    seekSum += v
                Next
                Console.WriteLine($"{name} rate={peep.Rate} channels={peep.Channels} frames={total} sum={sum} seek_sum={seekSum}")
            End Using
        Next
    End Sub
End Module
