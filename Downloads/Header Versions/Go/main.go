package main

import (
	"fmt"
	"os"

	"peepdemo/peep"
)

func sum(a []int16) (s int64) {
	for _, v := range a {
		s += int64(v)
	}
	return
}

func main() {
	for _, name := range []string{"test.wav", "test.flac"} {
		data, err := os.ReadFile(name)
		if err != nil {
			panic(err)
		}
		p, err := peep.New(data)
		if err != nil {
			panic(err)
		}
		var total, total_sum int64
		for {
			s := p.Read(1024)
			if len(s) == 0 {
				break
			}
			total += int64(len(s) / 2)
			total_sum += sum(s)
		}
		p.Seek(2205)
		seek_sum := sum(p.Read(100))
		fmt.Printf("%s rate=%d channels=%d frames=%d sum=%d seek_sum=%d\n", name, p.Rate(), p.Channels(), total, total_sum, seek_sum)
		p.Close()
	}
}
