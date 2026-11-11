# Liberated Peep for Raku (NativeCall)
unit class Peep;
use NativeCall;

sub peep-lib {
    my $name = $*DISTRO.is-win ?? 'peep.dll' !! 'libpeep.so';
    %*ENV<PEEP_LIB> // $*PROGRAM.parent.add($name).Str;
}
sub peep_open(CArray[uint8], CArray[uint64], CArray[uint8], size_t, CArray[uint8], size_t --> int32) is native(&peep-lib) {*}
sub peep_fill(CArray[uint8], CArray[int16], size_t --> size_t) is native(&peep-lib) {*}
sub peep_seek(CArray[uint8], uint64) is native(&peep-lib) {*}
sub peep_close(CArray[uint8]) is native(&peep-lib) {*}
sub peep_flac(--> Pointer) is native(&peep-lib) {*}

has CArray[uint8] $!p;
has CArray[uint64] $!codecs;
has CArray[uint8] $!data;
has CArray[uint8] $!work;
has CArray[int16] $!out;

sub zeroed(Int $n --> CArray[uint8]) { my $a = CArray[uint8].new; $a[$n - 1] = 0; $a }

# Peep.new(:$bytes) where $bytes is a Blob holding a WAV or FLAC file
submethod BUILD(Blob :$bytes!, Bool :$flac = True) {
    $!data = CArray[uint8].new($bytes.list);        # the library reads from this: keep it alive
    $!p = zeroed(160);                              # struct peep
    $!codecs = CArray[uint64].new;
    $!codecs[0] = $flac ?? +peep_flac() !! 0;       # address of the FLAC codec table
    $!codecs[1] = 0;
    unless peep_open($!p, $!codecs, $!data, $bytes.elems, CArray[uint8], 0) {
        my $need = self!u64(144);                   # work_need
        die 'not a playable WAV or FLAC file' unless $need;
        $!work = zeroed($need);
        die 'not a playable WAV or FLAC file' unless peep_open($!p, $!codecs, $!data, $bytes.elems, $!work, $need);
    }
    $!out = CArray[int16].new;
    $!out[4096 * 2 - 1] = 0;
}

method !u(Int $off, Int $n) { my $v = 0; for ^$n { $v += $!p[$off + $_] +< (8 * $_) }; $v }
method !u64(Int $off) { self!u($off, 8) }
method rate     { self!u(40, 4) }        # Hz
method channels { self!u(44, 4) }        # channels in the file
method total    { self!u(32, 8) }        # frames, 0 = unknown
method position { self!u(24, 8) }        # frames played so far

# Up to $frames stereo frames as a List of interleaved int16 values; empty at the end.
method read(Int $frames = 1024) {
    my $n = peep_fill($!p, $!out, min($frames, 4096));
    (^($n * 2)).map({ $!out[$_] }).List
}
method seek(Int $frame) { peep_seek($!p, $frame) }
method set-gain(Int $q8) {                       # volume 0..256 (256 = full)
    my $g = max(0, min(256, $q8));
    $!p[48 + $_] = ($g +> (8 * $_)) +& 0xFF for ^4;
}
method close { peep_close($!p) }
