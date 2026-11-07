use Peep;

my $here = $*PROGRAM.parent;
for <test.wav test.flac> -> $name {
    my $peep = Peep.new(bytes => $here.add($name).slurp(:bin));
    my ($total, $sum) = 0, 0;
    loop {
        my @s = $peep.read(1024);
        last unless @s;
        $total += @s.elems div 2;
        $sum += [+] @s;
    }
    $peep.seek(2205);
    my $seek-sum = [+] $peep.read(100);
    say "$name rate={$peep.rate} channels={$peep.channels} frames=$total sum=$sum seek_sum=$seek-sum";
    $peep.close;
}
