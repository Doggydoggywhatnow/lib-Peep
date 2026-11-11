package Peep;
# Liberated Peep for Perl (FFI::Platypus)
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;
use FFI::Platypus 2.00;
use FFI::Platypus::Buffer qw(scalar_to_buffer buffer_to_scalar);
use FFI::Platypus::Memory qw(malloc free memset memcpy);

my $lib = $ENV{PEEP_LIB} // File::Spec->catfile(dirname(__FILE__), $^O eq 'MSWin32' ? 'peep.dll' : 'libpeep.so');
-e $lib or die "libpeep not found: run ./build.sh first (or set PEEP_LIB)\n";
my $ffi = FFI::Platypus->new(api => 2, lib => $lib);
my $open  = $ffi->function(peep_open  => [qw(opaque opaque opaque size_t opaque size_t)] => 'int');
my $fill  = $ffi->function(peep_fill  => [qw(opaque opaque size_t)] => 'size_t');
my $seek  = $ffi->function(peep_seek  => [qw(opaque uint64)] => 'void');
my $close = $ffi->function(peep_close => ['opaque'] => 'void');
my $FLAC  = $ffi->function(peep_flac  => [] => 'opaque')->call;     # address of the FLAC codec table

sub _zeroed { my $p = malloc($_[0]); memset($p, 0, $_[0]); return $p }

# Peep->new($bytes): $bytes is a string holding a WAV or FLAC file
sub new {
    my ($class, $bytes, %opt) = @_;
    my $flac = exists $opt{flac} ? $opt{flac} : 1;
    my $self = bless { bytes => $bytes }, $class;                 # keep the data alive: the library reads from it
    my ($data, $len) = scalar_to_buffer($self->{bytes});
    $self->{p} = _zeroed(160);                                    # struct peep
    my $codecs = pack('QQ', $flac ? $FLAC : 0, 0);
    $self->{codecs} = _zeroed(16);
    my ($cp) = scalar_to_buffer($codecs);
    memcpy($self->{codecs}, $cp, 16);
    if (!$open->call($self->{p}, $self->{codecs}, $data, $len, 0, 0)) {
        my $need = unpack('Q', buffer_to_scalar($self->{p} + 144, 8));      # work_need
        die "not a playable WAV or FLAC file\n" unless $need;
        $self->{work} = _zeroed($need);
        $open->call($self->{p}, $self->{codecs}, $data, $len, $self->{work}, $need)
            or die "not a playable WAV or FLAC file\n";
    }
    $self->{out} = _zeroed(4096 * 4);
    return $self;
}

sub _u32 { unpack('V', buffer_to_scalar($_[0]{p} + $_[1], 4)) }
sub _u64 { unpack('Q', buffer_to_scalar($_[0]{p} + $_[1], 8)) }
sub rate     { $_[0]->_u32(40) }     # Hz
sub channels { $_[0]->_u32(44) }     # channels in the file
sub total    { $_[0]->_u64(32) }     # frames, 0 = unknown
sub position { $_[0]->_u64(24) }     # frames played so far

# Up to $frames stereo frames as an array ref of interleaved int16 values; empty at the end.
sub read {
    my ($self, $frames) = @_;
    $frames = 1024 unless defined $frames;
    my $n = $fill->call($self->{p}, $self->{out}, $frames > 4096 ? 4096 : $frames);
    return [] unless $n;
    return [ unpack('s*', buffer_to_scalar($self->{out}, $n * 4)) ];
}

sub seek { $seek->call($_[0]{p}, $_[1]) }

sub set_gain {                       # volume 0..256 (256 = full)
    my ($self, $q8) = @_;
    $q8 = 0 if $q8 < 0; $q8 = 256 if $q8 > 256;
    my $v = pack('V', $q8);
    my ($vp) = scalar_to_buffer($v);
    memcpy($self->{p} + 48, $vp, 4);
}

sub close { $close->call($_[0]{p}) }
1;
