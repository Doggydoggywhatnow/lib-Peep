use strict;
use warnings;
use FindBin qw($Bin);
use lib $Bin;
use List::Util qw(sum);
use Peep;

for my $name (qw(test.wav test.flac)) {
    open my $fh, '<:raw', "$Bin/$name" or die "$name: $!";
    my $bytes = do { local $/; <$fh> };
    close $fh;
    my $peep = Peep->new($bytes);
    my ($total, $sum) = (0, 0);
    while (1) {
        my $s = $peep->read(1024);
        last unless @$s;
        $total += @$s / 2;
        $sum += sum(@$s);
    }
    $peep->seek(2205);
    my $seek_sum = sum(@{ $peep->read(100) });
    printf "%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d\n",
        $name, $peep->rate, $peep->channels, $total, $sum, $seek_sum;
    $peep->close;
}
