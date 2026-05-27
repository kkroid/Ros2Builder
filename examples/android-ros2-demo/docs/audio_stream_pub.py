#!/usr/bin/env python3
"""
Stream audio from PC/WSL to the Android demo App.

Protocol expected by the App's native_bridge:
    /android/audio_control (std_msgs/String):
        "begin_stream:<rate>:<channels>:<sample_width>" -> live playback + saved wav
        "begin"                                          -> file-only mode
        "end_stream" | "end"                             -> finalize
    /android/audio_chunk (std_msgs/UInt8MultiArray): raw PCM bytes per chunk

Defaults: 16000 Hz, mono, 16-bit, 100 ms per chunk.

Usage:
    python3 audio_stream_pub.py --tone 440 --duration 5
    python3 audio_stream_pub.py --mic --duration 5
    python3 audio_stream_pub.py --wav sample.wav --speed 20
"""
from __future__ import annotations

import argparse
import math
import os
import select
import shutil
import struct
import subprocess
import sys
import time
import wave

import rclpy
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import MultiArrayDimension, String, UInt8MultiArray


CONTROL_TOPIC = "/android/audio_control"
CHUNK_TOPIC = "/android/audio_chunk"


def _qos_reliable(depth: int) -> QoSProfile:
    return QoSProfile(
        reliability=ReliabilityPolicy.RELIABLE,
        history=HistoryPolicy.KEEP_LAST,
        depth=depth,
    )


class AudioStreamPublisher(Node):
    def __init__(self) -> None:
        super().__init__("audio_stream_pub")
        self.control_pub = self.create_publisher(String, CONTROL_TOPIC, _qos_reliable(16))
        self.chunk_pub = self.create_publisher(UInt8MultiArray, CHUNK_TOPIC, _qos_reliable(64))

    def wait_for_subscribers(self, timeout: float = 5.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ctrl = self.control_pub.get_subscription_count()
            chunk = self.chunk_pub.get_subscription_count()
            if ctrl >= 1 and chunk >= 1:
                self.get_logger().info(f"matched subscribers control={ctrl} chunk={chunk}")
                return True
            rclpy.spin_once(self, timeout_sec=0.1)
        self.get_logger().warn(
            f"timeout waiting for subscribers: control={self.control_pub.get_subscription_count()} "
            f"chunk={self.chunk_pub.get_subscription_count()}"
        )
        return False

    def send_control(self, command: str) -> None:
        msg = String()
        msg.data = command
        self.control_pub.publish(msg)
        self.get_logger().info(f"control -> {command!r}")

    def send_chunk(self, data: bytes) -> None:
        msg = UInt8MultiArray()
        dim = MultiArrayDimension()
        dim.label = "bytes"
        dim.size = len(data)
        dim.stride = len(data)
        msg.layout.dim.append(dim)
        msg.layout.data_offset = 0
        msg.data = list(data)
        self.chunk_pub.publish(msg)

    def stream_pcm(
        self,
        pcm: bytes,
        rate: int,
        channels: int,
        width: int,
        chunk_ms: int,
        mode: str,
        speed: float,
    ) -> None:
        bytes_per_sample = channels * width
        samples_per_chunk = max(1, int(rate * chunk_ms / 1000))
        chunk_bytes = samples_per_chunk * bytes_per_sample

        if mode == "stream":
            self.send_control(f"begin_stream:{rate}:{channels}:{width}")
        else:
            self.send_control("begin")
        time.sleep(0.2)

        speed = max(1.0, speed)
        period = chunk_ms / 1000.0 / speed
        total = len(pcm)
        sent = 0
        next_t = time.monotonic()
        chunks = 0
        start = time.monotonic()
        while sent < total:
            end = min(sent + chunk_bytes, total)
            self.send_chunk(pcm[sent:end])
            sent = end
            chunks += 1
            next_t += period
            sleep = next_t - time.monotonic()
            if sleep > 0:
                time.sleep(sleep)
            else:
                next_t = time.monotonic()
            if chunks % 20 == 0:
                self.get_logger().info(
                    f"progress {sent}/{total} bytes ({sent * 100 // max(1, total)}%) "
                    f"chunks={chunks} speed={speed:.1f}x"
                )

        time.sleep(0.2)
        self.send_control("end_stream")
        elapsed = time.monotonic() - start
        audio_seconds = total / max(1, rate * bytes_per_sample)
        self.get_logger().info(
            f"done: {sent} bytes in {chunks} chunks over {elapsed:.2f}s "
            f"(target {audio_seconds:.2f}s of audio, speed={speed:.1f}x)"
        )


def load_wav(path: str) -> tuple[bytes, int, int, int]:
    with wave.open(path, "rb") as wav_file:
        rate = wav_file.getframerate()
        channels = wav_file.getnchannels()
        width = wav_file.getsampwidth()
        pcm = wav_file.readframes(wav_file.getnframes())
    return pcm, rate, channels, width


def generate_tone(freq: float, duration: float, rate: int = 16000) -> bytes:
    sample_count = int(duration * rate)
    samples = bytearray()
    amplitude = 0.4 * 32767
    for index in range(sample_count):
        value = int(amplitude * math.sin(2 * math.pi * freq * index / rate))
        samples.extend(struct.pack("<h", value))
    return bytes(samples)


def record_mic(duration: float, rate: int = 16000, source: str = "RDPSource") -> bytes:
    if not shutil.which("parec"):
        raise RuntimeError("parec not found; install pulseaudio-utils in WSL")
    env = os.environ.copy()
    env.setdefault("PULSE_SERVER", "unix:/mnt/wslg/PulseServer")
    cmd = [
        "parec",
        "--record",
        "--raw",
        f"--device={source}",
        f"--rate={rate}",
        "--channels=1",
        "--format=s16le",
    ]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    expected_bytes = max(1, int(duration * rate)) * 2
    chunks = []
    received = 0
    deadline = time.monotonic() + max(0.1, duration) + 2.0
    try:
        assert process.stdout is not None
        while received < expected_bytes and time.monotonic() < deadline:
            timeout = min(0.5, max(0.0, deadline - time.monotonic()))
            ready, _, _ = select.select([process.stdout], [], [], timeout)
            if not ready:
                continue
            data = process.stdout.read(min(8192, expected_bytes - received))
            if not data:
                break
            chunks.append(data)
            received += len(data)
        process.terminate()
        try:
            _, stderr = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            _, stderr = process.communicate()
    except Exception:
        process.kill()
        process.communicate()
        raise
    if process.returncode not in (0, -15):
        raise RuntimeError(stderr.decode("utf-8", errors="replace").strip() or "parec failed")
    return b"".join(chunks)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--wav", help="path to WAV file")
    source.add_argument("--tone", type=float, metavar="HZ", help="generate sine tone")
    source.add_argument("--mic", action="store_true", help="record WSLg microphone for --duration seconds")
    parser.add_argument("--duration", type=float, default=3.0, help="tone/mic duration seconds (default 3)")
    parser.add_argument("--mic-source", default="RDPSource", help="PulseAudio source for --mic (default RDPSource)")
    parser.add_argument("--chunk-ms", type=int, default=100, help="chunk size in milliseconds (default 100)")
    parser.add_argument("--mode", choices=["stream", "file"], default="stream",
                        help="stream=live playback (begin_stream); file=save only (begin)")
    parser.add_argument("--speed", type=float, default=1.0,
                        help="send pacing multiplier for TTS-like fast synthesis (default 1.0)")
    parser.add_argument("--wait", type=float, default=5.0, help="seconds to wait for subscriber match")
    args = parser.parse_args()

    if args.wav:
        pcm, rate, channels, width = load_wav(args.wav)
    elif args.tone is not None:
        rate, channels, width = 16000, 1, 2
        pcm = generate_tone(args.tone, args.duration, rate)
    else:
        rate, channels, width = 16000, 1, 2
        pcm = record_mic(args.duration, rate, args.mic_source)
        print(f"recorded {len(pcm)} bytes from {args.mic_source} over {args.duration:.2f}s", file=sys.stderr)

    if channels != 1 or width != 2:
        print(
            f"WARNING: App streaming playback expects mono 16-bit; got channels={channels} width={width}. "
            "Consider pre-converting: ffmpeg -i in.wav -ar 16000 -ac 1 -sample_fmt s16 out.wav",
            file=sys.stderr,
        )

    rclpy.init()
    try:
        node = AudioStreamPublisher()
        node.wait_for_subscribers(args.wait)
        node.stream_pcm(pcm, rate, channels, width, args.chunk_ms, args.mode, args.speed)
    finally:
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())