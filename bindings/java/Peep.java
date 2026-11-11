import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.nio.file.Files;
import java.nio.file.Path;

/** Liberated Peep for Java (java.lang.foreign). Decodes a WAV or FLAC file held in memory. */
public final class Peep implements AutoCloseable {
    private static final MethodHandle OPEN, FILL, SEEK, CLOSE;
    private static final long FLAC; // address of the FLAC codec table

    static {
        try {
            String name = System.getProperty("os.name").toLowerCase().contains("win") ? "peep.dll" : "libpeep.so";
            String env = System.getenv("PEEP_LIB");
            Path path = env != null ? Path.of(env) : Path.of(System.getProperty("user.dir"), name);
            if (!Files.exists(path)) throw new IllegalStateException("libpeep not found: run ./build.sh first (or set PEEP_LIB)");
            SymbolLookup lib = SymbolLookup.libraryLookup(path, Arena.global());
            Linker linker = Linker.nativeLinker();
            ValueLayout.OfInt I = ValueLayout.JAVA_INT;
            ValueLayout.OfLong L = ValueLayout.JAVA_LONG;
            var A = ValueLayout.ADDRESS;
            OPEN = linker.downcallHandle(lib.find("peep_open").orElseThrow(), FunctionDescriptor.of(I, A, A, A, L, A, L));
            FILL = linker.downcallHandle(lib.find("peep_fill").orElseThrow(), FunctionDescriptor.of(L, A, A, L));
            SEEK = linker.downcallHandle(lib.find("peep_seek").orElseThrow(), FunctionDescriptor.ofVoid(A, L));
            CLOSE = linker.downcallHandle(lib.find("peep_close").orElseThrow(), FunctionDescriptor.ofVoid(A));
            MethodHandle flac = linker.downcallHandle(lib.find("peep_flac").orElseThrow(), FunctionDescriptor.of(A));
            FLAC = ((MemorySegment) flac.invokeExact()).address();
        } catch (Throwable t) {
            throw new ExceptionInInitializerError(t);
        }
    }

    private final Arena arena = Arena.ofConfined();
    private final MemorySegment p, data, codecs, out;
    private MemorySegment work = MemorySegment.NULL;

    /** @param bytes a WAV or FLAC file */
    public Peep(byte[] bytes) {
        data = arena.allocate(bytes.length);                  // the library reads from this: keep it alive
        MemorySegment.copy(MemorySegment.ofArray(bytes), 0, data, 0, bytes.length);
        p = arena.allocate(160, 8);                           // struct peep (zeroed)
        codecs = arena.allocate(16, 8);
        codecs.set(ValueLayout.JAVA_LONG, 0, FLAC);
        try {
            if ((int) OPEN.invokeExact(p, codecs, data, (long) bytes.length, MemorySegment.NULL, 0L) == 0) {
                long need = p.get(ValueLayout.JAVA_LONG, 144);   // work_need
                if (need == 0) throw new IllegalArgumentException("not a playable WAV or FLAC file");
                work = arena.allocate(need, 16);
                if ((int) OPEN.invokeExact(p, codecs, data, (long) bytes.length, work, need) == 0)
                    throw new IllegalArgumentException("not a playable WAV or FLAC file");
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Throwable t) {
            throw new RuntimeException(t);
        }
        out = arena.allocate(4096L * 4, 8);
    }

    public int rate() { return p.get(ValueLayout.JAVA_INT, 40); }         // Hz
    public int channels() { return p.get(ValueLayout.JAVA_INT, 44); }     // channels in the file
    public long total() { return p.get(ValueLayout.JAVA_LONG, 32); }      // frames, 0 = unknown
    public long position() { return p.get(ValueLayout.JAVA_LONG, 24); }   // frames played so far

    /** Up to {@code frames} stereo frames as interleaved samples; empty at the end. */
    public short[] read(int frames) {
        try {
            long n = (long) FILL.invokeExact(p, out, (long) Math.min(frames, 4096));
            short[] s = new short[(int) n * 2];
            MemorySegment.copy(out, ValueLayout.JAVA_SHORT, 0, s, 0, s.length);
            return s;
        } catch (Throwable t) {
            throw new RuntimeException(t);
        }
    }

    public void seek(long frame) {
        try { SEEK.invokeExact(p, frame); } catch (Throwable t) { throw new RuntimeException(t); }
    }

    /** Volume 0..256 (256 = full). */
    public void setGain(int q8) { p.set(ValueLayout.JAVA_INT, 48, Math.max(0, Math.min(256, q8))); }

    @Override
    public void close() {
        try { CLOSE.invokeExact(p); } catch (Throwable t) { throw new RuntimeException(t); }
        arena.close();
    }
}
