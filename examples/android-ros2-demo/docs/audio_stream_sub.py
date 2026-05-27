#!/usr/bin/env python3
"""
Receive audio stream from the Android demo App on PC and play it live.

Subscribes:
    /wsl/audio_control (std_msgs/String):
        "begin_stream:<rate>:<channels>:<sample_width>"
        "end_stream" | "end"
    /wsl/audio_chunk (std_msgs/UInt8MultiArray)  -> raw PCM bytes

Playback backend: pacat (PulseAudio/WSLg) by default. Stdin is fed raw PCM,
format derived from begin_stream. Stops + restarts the player on each new begin_stream.

Usage:
    python audio_stream_sub.py
    python audio_stream_sub.py --save out.wav            # also save received PCM as WAV
    python audio_stream_sub.py --player aplay            # use ALSA aplay instead of pacat
    python audio_stream_sub.py --player play             # use 'play' (sox) instead of pacat
"""
from __future__ import annotations

import argparse
from collections import deque
import os
import shutil
import subprocess
import sys
import threading
import wave
from typing import Deque, Optional

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from std_msgs.msg import String, UInt8MultiArray


CONTROL_TOPIC = "/wsl/audio_control"
CHUNK_TOPIC = "/wsl/audio_chunk"


def _qos_reliable(depth: int) -> QoSProfile:
    return QoSProfile(
        reliability=ReliabilityPolicy.RELIABLE,
        history=HistoryPolicy.KEEP_LAST,
        depth=depth,
    )


class AudioStreamSubscriber(Node):
    def __init__(self, player: str, save_path: Optional[str]) -> None:
        super().__init__("audio_stream_sub")
        self.player = player
        self.save_path = save_path
        self.process: Optional[subprocess.Popen[bytes]] = None
        self.wav_writer: Optional[wave.Wave_write] = None
        self.rate = 16000
        self.channels = 1
        self.width = 2
        self.received_bytes = 0
        self.received_chunks = 0
        self.buffer: Deque[bytes] = deque()
        self.buffered_bytes = 0
        self.buffer_cond = threading.Condition()
        self.play_thread: Optional[threading.Thread] = None
        self.stream_open = False
        self.create_subscription(String, CONTROL_TOPIC, self._on_control, _qos_reliable(16))
        self.create_subscription(UInt8MultiArray, CHUNK_TOPIC, self._on_chunk, _qos_reliable(64))
        self.get_logger().info(
            f"listening on {CONTROL_TOPIC} and {CHUNK_TOPIC}; player={player}"
            + (f"; saving to {save_path}" if save_path else "")
        )

    def _on_control(self, msg: String) -> None:
        cmd = msg.data.strip()
        self.get_logger().info(f"control <- {cmd!r}")
        if cmd.startswith("begin_stream:"):
            parts = cmd[len("begin_stream:"):].split(":")
            try:
                self.rate = int(parts[0])
                self.channels = int(parts[1])
                self.width = int(parts[2])
            except (IndexError, ValueError):
                self.get_logger().warn(f"bad begin_stream args: {cmd!r}, using {self.rate}/{self.channels}/{self.width}")
            self._start_stream()
        elif cmd.startswith("begin"):
            # File-only mode: we still play it. (Same fields, just no preceding stream-config.)
            self._start_stream()
        elif cmd in ("end_stream", "end"):
            self._end_stream()

    def _on_chunk(self, msg: UInt8MultiArray) -> None:
        data = bytes(msg.data)
        if not data:
            return
        self.received_bytes += len(data)
        self.received_chunks += 1
        if self.process is None:
            # No begin yet; auto-start a stream with last-known parameters.
            self.get_logger().warn("got chunk before begin_stream; auto-starting with defaults")
            self._start_stream()
        with self.buffer_cond:
            self.buffer.append(data)
            self.buffered_bytes += len(data)
            buffered = self.buffered_bytes
            self.buffer_cond.notify()
        if self.wav_writer is not None:
            self.wav_writer.writeframes(data)
        if self.received_chunks % 20 == 0:
            buffered_seconds = buffered / max(1, self.rate * self.channels * self.width)
            self.get_logger().info(
                f"received {self.received_bytes} bytes in {self.received_chunks} chunks; "
                f"playback buffer={buffered_seconds:.1f}s"
            )

    def _start_stream(self) -> None:
        self._end_stream()
        self.received_bytes = 0
        self.received_chunks = 0
        env = None
        if self.player == "pacat":
            fmt = {1: "u8", 2: "s16le", 3: "s24le", 4: "s32le"}.get(self.width, "s16le")
            cmd = [
                "pacat",
                "--playback",
                "--raw",
                "--device=RDPSink",
                f"--format={fmt}",
                f"--rate={self.rate}",
                f"--channels={self.channels}",
            ]
            env = os.environ.copy()
            env.setdefault("PULSE_SERVER", "unix:/mnt/wslg/PulseServer")
        elif self.player == "aplay":
            fmt = {1: "U8", 2: "S16_LE", 3: "S24_LE", 4: "S32_LE"}.get(self.width, "S16_LE")
            cmd = [
                "aplay", "-q",
                "-t", "raw",
                "-f", fmt,
                "-r", str(self.rate),
                "-c", str(self.channels),
            ]
        elif self.player == "play":
            cmd = [
                "play", "-q",
                "-t", "raw",
                "-r", str(self.rate),
                "-b", str(self.width * 8),
                "-c", str(self.channels),
                "-e", "signed-integer",
                "-",
            ]
        else:
            raise SystemExit(f"unknown player: {self.player}")
        if not shutil.which(cmd[0]):
            raise SystemExit(
                f"player '{cmd[0]}' not found. Install it (e.g. `sudo apt-get install alsa-utils`) "
                f"or pick another with --player."
            )
        self.get_logger().info(f"start playback: {' '.join(cmd)}")
        self.process = subprocess.Popen(cmd, stdin=subprocess.PIPE, env=env)
        with self.buffer_cond:
            self.buffer.clear()
            self.buffered_bytes = 0
            self.stream_open = True
        self.play_thread = threading.Thread(target=self._playback_loop, name="audio-playback", daemon=True)
        self.play_thread.start()
        if self.save_path:
            self.wav_writer = wave.open(self.save_path, "wb")
            self.wav_writer.setnchannels(self.channels)
            self.wav_writer.setsampwidth(self.width)
            self.wav_writer.setframerate(self.rate)

    def _playback_loop(self) -> None:
        while True:
            with self.buffer_cond:
                while self.stream_open and not self.buffer:
                    self.buffer_cond.wait()
                if not self.buffer:
                    break
                data = self.buffer.popleft()
                self.buffered_bytes -= len(data)
            try:
                if self.process is None or self.process.stdin is None:
                    return
                self.process.stdin.write(data)
                self.process.stdin.flush()
            except BrokenPipeError:
                self.get_logger().error("player exited; dropping buffered audio")
                return

    def _end_stream(self, drain: bool = True) -> None:
        with self.buffer_cond:
            self.stream_open = False
            buffered = self.buffered_bytes
            self.buffer_cond.notify_all()
        if buffered:
            buffered_seconds = buffered / max(1, self.rate * self.channels * self.width)
            self.get_logger().info(f"receive complete; draining playback buffer={buffered_seconds:.1f}s")
        if self.play_thread is not None:
            if drain:
                self.play_thread.join()
            else:
                with self.buffer_cond:
                    self.buffer.clear()
                    self.buffered_bytes = 0
                    self.buffer_cond.notify_all()
                self.play_thread.join(timeout=1)
            self.play_thread = None
        if self.process is not None:
            try:
                if self.process.stdin is not None:
                    self.process.stdin.close()
            except Exception:  # noqa: BLE001
                pass
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
            self.process = None
            self.get_logger().info(
                f"stream end: {self.received_bytes} bytes in {self.received_chunks} chunks"
            )
        if self.wav_writer is not None:
            self.wav_writer.close()
            self.wav_writer = None
            self.get_logger().info(f"wrote {self.save_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--player", choices=["pacat", "aplay", "play"], default="pacat",
                        help="playback backend (default pacat for WSLg/PulseAudio)")
    parser.add_argument("--save", metavar="PATH", help="also save the received PCM as a WAV file")
    args = parser.parse_args()

    rclpy.init()
    try:
        node = AudioStreamSubscriber(args.player, args.save)
        try:
            rclpy.spin(node)
        except KeyboardInterrupt:
            pass
        finally:
            node._end_stream(drain=False)  # noqa: SLF001
            node.destroy_node()
    finally:
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
