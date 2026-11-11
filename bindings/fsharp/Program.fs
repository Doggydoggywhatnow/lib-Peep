open System.IO
open LiberatedPeep

for name in [ "test.wav"; "test.flac" ] do
    use peep = new Peep(File.ReadAllBytes(Path.Combine(Directory.GetCurrentDirectory(), name)))
    let mutable total = 0L
    let mutable sum = 0L
    let mutable go = true
    while go do
        let s = peep.Read 1024
        if s.Length = 0 then
            go <- false
        else
            total <- total + int64 (s.Length / 2)
            sum <- sum + (s |> Array.sumBy int64)
    peep.Seek 2205UL
    let seekSum = peep.Read 100 |> Array.sumBy int64
    printfn "%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d" name peep.Rate peep.Channels total sum seekSum
