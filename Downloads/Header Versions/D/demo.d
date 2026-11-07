import peep;
import std.file : read;
import std.stdio : writefln;

void main()
{
    foreach (name; ["test.wav", "test.flac"])
    {
        auto p = new Peep(cast(const(ubyte)[]) read(name));
        long total = 0, sum = 0;
        for (;;)
        {
            auto s = p.read(1024);
            if (s.length == 0) break;
            total += s.length / 2;
            foreach (v; s) sum += v;
        }
        p.seek(2205);
        long seekSum = 0;
        foreach (v; p.read(100)) seekSum += v;
        writefln("%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d", name, p.rate, p.channels, total, sum, seekSum);
        p.close();
    }
}
