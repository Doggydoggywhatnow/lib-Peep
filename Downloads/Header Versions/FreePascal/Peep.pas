{ Liberated Peep for Free Pascal: external declarations, no other units needed. }
unit Peep;
{$mode objfpc}{$H+}
{$linklib c}   { FPC does not link libc by default; without it a program that loads a shared library crashes at exit }

interface

type
  TSamples = array of SmallInt;

  { Decodes a WAV or FLAC file held in memory into stereo 16-bit samples. }
  TPeep = class
  private
    FP: array[0..19] of QWord;       { struct peep: 160 bytes, 8-aligned }
    FData: array of Byte;            { the library reads from this: it must stay alive }
    FCodecs: array[0..1] of Pointer;
    FWork: array of QWord;
    FOut: array of SmallInt;
    function GetU32(Off: Integer): LongWord;
    function GetU64(Off: Integer): QWord;
  public
    { Bytes: a WAV or FLAC file }
    constructor Create(const Bytes: array of Byte);
    function Read(Frames: Integer = 1024): TSamples;   { up to Frames stereo frames, interleaved; empty at the end }
    procedure Seek(Frame: QWord);
    procedure SetGain(Q8: Integer);                    { volume 0..256 (256 = full) }
    procedure Close;
    function Rate: LongWord;                           { Hz }
    function Channels: LongWord;                       { channels in the file }
    function Total: QWord;                             { frames, 0 = unknown }
    function Position: QWord;                          { frames played so far }
  end;

implementation

uses SysUtils;

function peep_open(p, codecs, data: Pointer; len: PtrUInt; work: Pointer; workSize: PtrUInt): LongInt; cdecl; external 'peep';
function peep_fill(p, outBuf: Pointer; frames: PtrUInt): PtrUInt; cdecl; external 'peep';
procedure peep_seek(p: Pointer; frame: QWord); cdecl; external 'peep';
procedure peep_close(p: Pointer); cdecl; external 'peep';
function peep_flac: Pointer; cdecl; external 'peep';   { address of the FLAC codec table }

constructor TPeep.Create(const Bytes: array of Byte);
var
  Need: PtrUInt;
begin
  inherited Create;
  SetLength(FData, Length(Bytes));
  if Length(Bytes) > 0 then Move(Bytes[0], FData[0], Length(Bytes));
  SetLength(FOut, 4096 * 2);
  FillChar(FP, SizeOf(FP), 0);
  FCodecs[0] := peep_flac;
  FCodecs[1] := nil;
  if (Length(FData) = 0) or (peep_open(@FP, @FCodecs, @FData[0], Length(FData), nil, 0) = 0) then
  begin
    Need := PtrUInt(FP[18]);                           { work_need (offset 144) }
    if (Length(FData) = 0) or (Need = 0) then raise Exception.Create('not a playable WAV or FLAC file');
    SetLength(FWork, (Need + 7) div 8);
    FillChar(FWork[0], Length(FWork) * 8, 0);
    if peep_open(@FP, @FCodecs, @FData[0], Length(FData), @FWork[0], Need) = 0 then
      raise Exception.Create('not a playable WAV or FLAC file');
  end;
end;

function TPeep.GetU32(Off: Integer): LongWord;
begin
  Result := PLongWord(PByte(@FP) + Off)^;
end;

function TPeep.GetU64(Off: Integer): QWord;
begin
  Result := PQWord(PByte(@FP) + Off)^;
end;

function TPeep.Rate: LongWord; begin Result := GetU32(40); end;
function TPeep.Channels: LongWord; begin Result := GetU32(44); end;
function TPeep.Total: QWord; begin Result := GetU64(32); end;
function TPeep.Position: QWord; begin Result := GetU64(24); end;

function TPeep.Read(Frames: Integer): TSamples;
var
  N: Integer;
begin
  if Frames > 4096 then Frames := 4096;
  N := Integer(peep_fill(@FP, @FOut[0], Frames));
  SetLength(Result, N * 2);
  if N > 0 then Move(FOut[0], Result[0], N * 4);
end;

procedure TPeep.Seek(Frame: QWord);
begin
  peep_seek(@FP, Frame);
end;

procedure TPeep.SetGain(Q8: Integer);
begin
  if Q8 < 0 then Q8 := 0;
  if Q8 > 256 then Q8 := 256;
  PLongWord(PByte(@FP) + 48)^ := LongWord(Q8);
end;

procedure TPeep.Close;
begin
  peep_close(@FP);
end;

end.
