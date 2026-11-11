<?php
require __DIR__ . '/peep.php';

foreach (['test.wav', 'test.flac'] as $name) {
    $peep = new Peep(file_get_contents(__DIR__ . '/' . $name));
    $total = 0;
    $sum = 0;
    while ($samples = $peep->read(1024)) {
        $total += intdiv(count($samples), 2);
        $sum += array_sum($samples);
    }
    $peep->seek(2205);
    $seekSum = array_sum($peep->read(100));
    printf("%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d\n", $name, $peep->rate(), $peep->channels(), $total, $sum, $seekSum);
    $peep->close();
}
