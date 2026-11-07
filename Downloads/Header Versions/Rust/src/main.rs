mod peep;
use peep::Peep;

fn main() {
    let dir = env!("CARGO_MANIFEST_DIR");
    for name in ["test.wav", "test.flac"] {
        let data = std::fs::read(format!("{dir}/{name}")).expect("test file");
        let mut p = Peep::new(&data).expect("open");
        let (mut total, mut sum) = (0i64, 0i64);
        loop {
            let s = p.read(1024);
            if s.is_empty() { break; }
            total += (s.len() / 2) as i64;
            sum += s.iter().map(|&v| v as i64).sum::<i64>();
        }
        p.seek(2205);
        let seek_sum: i64 = p.read(100).iter().map(|&v| v as i64).sum();
        println!("{name} rate={} channels={} frames={total} sum={sum} seek_sum={seek_sum}", p.rate(), p.channels());
        p.close();
    }
}
