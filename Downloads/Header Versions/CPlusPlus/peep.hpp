// Liberated Peep for C++17 (header only). Declares the C ABI itself; no C header needed.
#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <stdexcept>
#include <vector>

extern "C" {
int peep_open(void *p, const void *codecs, const void *data, std::size_t len, void *work, std::size_t work_size);
std::size_t peep_fill(void *p, std::int16_t *out, std::size_t frames);
void peep_seek(void *p, std::uint64_t frame);
void peep_close(void *p);
const void *peep_flac(void);   // address of the FLAC codec table
}

namespace peep {

// Decodes a WAV or FLAC file held in memory into stereo 16-bit samples.
class Peep {
public:
    // data: a WAV or FLAC file. The bytes are copied; the library reads from the copy.
    explicit Peep(const std::vector<std::uint8_t> &data, bool flac = true)
        : data_(data), codecs_{flac ? reinterpret_cast<std::uintptr_t>(peep_flac()) : 0, 0}, out_(4096 * 2) {
        std::memset(p_, 0, sizeof p_);
        if (!peep_open(p_, codecs_, data_.data(), data_.size(), nullptr, 0)) {
            std::uint64_t need = get<std::uint64_t>(144);                 // work_need
            if (!need) throw std::invalid_argument("not a playable WAV or FLAC file");
            work_.assign((need + 7) / 8, 0);
            if (!peep_open(p_, codecs_, data_.data(), data_.size(), work_.data(), need))
                throw std::invalid_argument("not a playable WAV or FLAC file");
        }
    }
    Peep(const Peep &) = delete;
    Peep &operator=(const Peep &) = delete;
    ~Peep() { peep_close(p_); }

    std::uint32_t rate() const { return get<std::uint32_t>(40); }         // Hz
    std::uint32_t channels() const { return get<std::uint32_t>(44); }     // channels in the file
    std::uint64_t total() const { return get<std::uint64_t>(32); }        // frames, 0 = unknown
    std::uint64_t position() const { return get<std::uint64_t>(24); }     // frames played so far

    // Up to `frames` stereo frames as interleaved int16 values; empty at the end.
    std::vector<std::int16_t> read(std::size_t frames = 1024) {
        std::size_t n = peep_fill(p_, out_.data(), std::min<std::size_t>(frames, 4096));
        return std::vector<std::int16_t>(out_.begin(), out_.begin() + n * 2);
    }
    void seek(std::uint64_t frame) { peep_seek(p_, frame); }
    void set_gain(unsigned q8) {                                          // volume 0..256 (256 = full)
        std::uint32_t g = std::min(q8, 256u);
        std::memcpy(p_ + 48, &g, 4);
    }

private:
    template <class T> T get(std::size_t off) const { T v; std::memcpy(&v, p_ + off, sizeof v); return v; }
    alignas(16) unsigned char p_[160];          // struct peep
    std::vector<std::uint8_t> data_;            // the library reads from this
    std::uintptr_t codecs_[2];
    std::vector<std::uint64_t> work_;
    std::vector<std::int16_t> out_;
};

}  // namespace peep
