#pragma once

#include <cstdint>
#include <iosfwd>
#include <string>

struct WavInfo {
  uint32_t sample_rate = 0;
  uint16_t channels = 0;
  uint16_t sample_width = 0;
  uint32_t data_offset = 0;
  uint32_t data_bytes = 0;
};

bool read_wav_info(const std::string &path, WavInfo &info, std::string &error);
void write_wav_header(std::ostream &stream, uint32_t sample_rate, uint16_t channels,
                      uint16_t sample_width, uint32_t pcm_bytes);