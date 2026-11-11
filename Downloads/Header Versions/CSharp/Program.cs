using LiberatedPeep;

foreach (var name in new[] { "test.wav", "test.flac" })
{
    using var peep = new Peep(File.ReadAllBytes(Path.Combine(Directory.GetCurrentDirectory(), name)));
    long total = 0, sum = 0;
    for (;;)
    {
        var s = peep.Read(1024);
        if (s.Length == 0) break;
        total += s.Length / 2;
        foreach (var v in s) sum += v;
    }
    peep.Seek(2205);
    long seekSum = 0;
    foreach (var v in peep.Read(100)) seekSum += v;
    Console.WriteLine($"{name} rate={peep.Rate} channels={peep.Channels} frames={total} sum={sum} seek_sum={seekSum}");
}
