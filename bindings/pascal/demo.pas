program Demo;
{$mode objfpc}{$H+}

uses SysUtils, Classes, Peep;

function Slurp(const Path: string): TBytes;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmOpenRead);
  try
    SetLength(Result, F.Size);
    F.ReadBuffer(Result[0], F.Size);
  finally
    F.Free;
  end;
end;

const
  Names: array[0..1] of string = ('test.wav', 'test.flac');
var
  I, K: Integer;
  P: TPeep;
  S: TSamples;
  Total, Sum, SeekSum: Int64;
begin
  for I := 0 to 1 do
  begin
    P := TPeep.Create(Slurp(Names[I]));
    Total := 0; Sum := 0; SeekSum := 0;
    repeat
      S := P.Read(1024);
      Total := Total + Length(S) div 2;
      for K := 0 to High(S) do Sum := Sum + S[K];
    until Length(S) = 0;
    P.Seek(2205);
    S := P.Read(100);
    for K := 0 to High(S) do SeekSum := SeekSum + S[K];
    WriteLn(Format('%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d', [Names[I], P.Rate, P.Channels, Total, Sum, SeekSum]));
    P.Close;
    P.Free;
  end;
end.
