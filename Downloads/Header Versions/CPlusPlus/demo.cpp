#include <cstdio>
#include <fstream>
#include <iterator>
#include "peep.hpp"

static std::vector<std::uint8_t> slurp(const char *path) {
    std::ifstream f(path, std::ios::binary);
    return std::vector<std::uint8_t>(std::istreambuf_iterator<char>(f), {});
}

int main() {
    for (const char *name : {"test.wav", "test.flac"}) {
        peep::Peep p(slurp(name));
        long long total = 0, sum = 0;
        for (;;) {
            auto s = p.read(1024);
            if (s.empty()) break;
            total += s.size() / 2;
            for (auto v : s) sum += v;
        }
        p.seek(2205);
        long long seek_sum = 0;
        for (auto v : p.read(100)) seek_sum += v;
        std::printf("%s rate=%u channels=%u frames=%lld sum=%lld seek_sum=%lld\n", name, p.rate(), p.channels(), total, sum, seek_sum);
    }
}
