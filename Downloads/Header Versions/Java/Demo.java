import java.nio.file.Files;
import java.nio.file.Path;

public class Demo {
    static long sum(short[] a) { long s = 0; for (short v : a) s += v; return s; }

    public static void main(String[] args) throws Exception {
        for (String name : new String[] {"test.wav", "test.flac"}) {
            try (Peep peep = new Peep(Files.readAllBytes(Path.of(name)))) {
                long total = 0, totalSum = 0;
                for (;;) {
                    short[] s = peep.read(1024);
                    if (s.length == 0) break;
                    total += s.length / 2;
                    totalSum += sum(s);
                }
                peep.seek(2205);
                long seekSum = sum(peep.read(100));
                System.out.printf("%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d%n", name, peep.rate(), peep.channels(), total, totalSum, seekSum);
            }
        }
    }
}
