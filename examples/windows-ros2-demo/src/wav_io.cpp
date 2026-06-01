#include "wav_io.h"

#include <fstream>

namespace {

uint16_t read_u16(std::istream &stream) {
  uint8_t bytes[2] = {};
  stream.read(reinterpret_cast<char *>(bytes), sizeof(bytes));
  return static_cast<uint16_t>(bytes[0] | (bytes[1] << 8));
}

uint32_t read_u32(std::istream &stream) {
  uint8_t bytes[4] = {};
  stream.read(reinterpret_cast<char *>(bytes), sizeof(bytes));
  return static_cast<uint32_t>(bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24));
}

void write_ascii(std::ostream &stream, const char *value) {
  stream.write(value, 4);
}

void write_u16(std::ostream &stream, uint16_t value) {
  const char bytes[2] = {
      static_cast<char>(value & 0xff),
      static_cast<char>((value >> 8) & 0xff),
  };
  stream.write(bytes, sizeof(bytes));
}

void write_u32(std::ostream &stream, uint32_t value) {
  const char bytes[4] = {
      static_cast<char>(value & 0xff),
      static_cast<char>((value >> 8) & 0xff),
      static_cast<char>((value >> 16) & 0xff),
      static_cast<char>((value >> 24) & 0xff),
  };
  stream.write(bytes, sizeof(bytes));
}

bool read_tag(std::istream &stream, const char expected[4]) {
  char tag[4] = {};
  stream.read(tag, sizeof(tag));
  return stream && tag[0] == expected[0] && tag[1] == expected[1] &&
         tag[2] == expected[2] && tag[3] == expected[3];
}

}  // namespace

bool read_wav_info(const std::string &path, WavInfo &info, std::string &error) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) {
    error = "Failed to open WAV file";
    return false;
  }
  if (!read_tag(stream, "RIFF")) {
    error = "Missing RIFF header";
    return false;
  }
  read_u32(stream);
  if (!read_tag(stream, "WAVE")) {
    error = "Missing WAVE header";
    return false;
  }

  bool found_format = false;
  bool found_data = false;
  uint16_t format_tag = 0;
  while (stream && (!found_format || !found_data)) {
    char chunk_id[4] = {};
    stream.read(chunk_id, sizeof(chunk_id));
    if (!stream) {
      break;
    }
    uint32_t chunk_size = read_u32(stream);
    const auto chunk_start = stream.tellg();
    if (chunk_id[0] == 'f' && chunk_id[1] == 'm' && chunk_id[2] == 't' && chunk_id[3] == ' ') {
      format_tag = read_u16(stream);
      info.channels = read_u16(stream);
      info.sample_rate = read_u32(stream);
      read_u32(stream);
      read_u16(stream);
      info.sample_width = static_cast<uint16_t>(read_u16(stream) / 8);
      found_format = true;
    } else if (chunk_id[0] == 'd' && chunk_id[1] == 'a' && chunk_id[2] == 't' && chunk_id[3] == 'a') {
      info.data_offset = static_cast<uint32_t>(stream.tellg());
      info.data_bytes = chunk_size;
      found_data = true;
    }
    stream.seekg(static_cast<std::streamoff>(chunk_start) + chunk_size + (chunk_size & 1), std::ios::beg);
  }

  if (!found_format || !found_data) {
    error = "Missing WAV fmt or data chunk";
    return false;
  }
  if (format_tag != 1 || info.sample_width != 2) {
    error = "Only 16-bit PCM WAV files are supported";
    return false;
  }
  if (info.channels != 1) {
    error = "Only mono WAV files are supported by the Android demo receiver";
    return false;
  }
  return true;
}

void write_wav_header(std::ostream &stream, uint32_t sample_rate, uint16_t channels,
                      uint16_t sample_width, uint32_t pcm_bytes) {
  stream.seekp(0, std::ios::beg);
  write_ascii(stream, "RIFF");
  write_u32(stream, 36 + pcm_bytes);
  write_ascii(stream, "WAVE");
  write_ascii(stream, "fmt ");
  write_u32(stream, 16);
  write_u16(stream, 1);
  write_u16(stream, channels);
  write_u32(stream, sample_rate);
  write_u32(stream, sample_rate * channels * sample_width);
  write_u16(stream, static_cast<uint16_t>(channels * sample_width));
  write_u16(stream, static_cast<uint16_t>(sample_width * 8));
  write_ascii(stream, "data");
  write_u32(stream, pcm_bytes);
  stream.seekp(0, std::ios::end);
}