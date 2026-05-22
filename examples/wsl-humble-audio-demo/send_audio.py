#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import time
import wave
from array import array
from pathlib import Path

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from std_msgs.msg import String, UInt8MultiArray


class AudioSender(Node):
    def __init__(self, qos_mode):
        super().__init__('wsl_humble_audio_sender')
        qos = self._make_qos(qos_mode)
        self.control_publisher = self.create_publisher(
            String,
            os.environ.get(
                'ANDROID_AUDIO_CONTROL_TOPIC',
                '/android/audio_control',
            ),
            qos,
        )
        self.chunk_publisher = self.create_publisher(
            UInt8MultiArray,
            os.environ.get(
                'ANDROID_AUDIO_CHUNK_TOPIC',
                '/android/audio_chunk',
            ),
            qos,
        )

    def _make_qos(self, qos_mode):
        qos = QoSProfile(depth=10)
        if qos_mode == 'best_effort':
            qos.reliability = ReliabilityPolicy.BEST_EFFORT
        else:
            qos.reliability = ReliabilityPolicy.RELIABLE
        return qos

    def wait_for_subscribers(self, timeout_sec):
        deadline = time.monotonic() + timeout_sec
        while time.monotonic() < deadline:
            control_count = self.control_publisher.get_subscription_count()
            chunk_count = self.chunk_publisher.get_subscription_count()
            if control_count > 0 and chunk_count > 0:
                self.get_logger().info(
                    'Android audio subscribers matched: '
                    f'control={control_count}, chunk={chunk_count}'
                )
                return True
            rclpy.spin_once(self, timeout_sec=0.1)

        control_count = self.control_publisher.get_subscription_count()
        chunk_count = self.chunk_publisher.get_subscription_count()
        self.get_logger().warning(
            'Timed out waiting for Android audio subscribers: '
            f'control={control_count}, chunk={chunk_count}'
        )
        return False

    def begin_stream(self, rate, channels):
        control = String()
        control.data = f'begin_stream:{rate}:{channels}:2'
        self.control_publisher.publish(control)
        rclpy.spin_once(self, timeout_sec=0.2)
        time.sleep(0.2)

    def publish_chunk(self, chunk):
        message = UInt8MultiArray()
        message.data = array('B', chunk)
        self.chunk_publisher.publish(message)
        rclpy.spin_once(self, timeout_sec=0)

    def end_stream(self):
        control = String()
        control.data = 'end_stream'
        self.control_publisher.publish(control)
        rclpy.spin_once(self, timeout_sec=0.2)

    def stream_wav_file(
        self,
        wav_path,
        chunk_size,
        publish_delay,
        discovery_timeout,
    ):
        wav_path = Path(wav_path)
        if not self.wait_for_subscribers(discovery_timeout):
            raise SystemExit('Android audio subscribers were not discovered.')

        with wave.open(str(wav_path), 'rb') as wav_file:
            rate = wav_file.getframerate()
            channels = wav_file.getnchannels()
            sample_width = wav_file.getsampwidth()
            if sample_width != 2:
                raise SystemExit('Only 16-bit PCM WAV files are supported.')
            total_frames = wav_file.getnframes()
            total_bytes = total_frames * channels * sample_width
            self.get_logger().info(
                f'streaming {wav_path} ({total_bytes} PCM bytes)'
            )
            self.begin_stream(rate, channels)

            chunk_count = 0
            frames_per_chunk = max(1, chunk_size // (channels * sample_width))
            while True:
                chunk = wav_file.readframes(frames_per_chunk)
                if not chunk:
                    break
                self.publish_chunk(chunk)
                chunk_count += 1
                if publish_delay > 0:
                    time.sleep(publish_delay)

        self.end_stream()
        self.get_logger().info(
            f'audio stream complete: chunks={chunk_count}, bytes={total_bytes}'
        )

    def stream_recording(
        self,
        duration,
        rate,
        channels,
        source,
        chunk_size,
        publish_delay,
        discovery_timeout,
        countdown,
        keep_wav,
    ):
        if not self.wait_for_subscribers(discovery_timeout):
            raise SystemExit('Android audio subscribers were not discovered.')
        stream_recording_with_parec(
            self,
            duration,
            rate,
            channels,
            source,
            chunk_size,
            publish_delay,
            countdown,
            keep_wav,
        )


def run_countdown(seconds):
    if seconds <= 0:
        return
    print(f'>>> RECORDING STARTS IN {seconds} SECONDS <<<', flush=True)
    for remaining in range(seconds, 0, -1):
        print(f'>>> {remaining} <<<', flush=True)
        time.sleep(1)


def stream_recording_with_parec(
    sender,
    duration,
    rate,
    channels,
    source,
    chunk_size,
    publish_delay,
    countdown,
    keep_wav,
):
    if shutil.which('parec') is None:
        raise SystemExit(
            'parec is missing. Install pulseaudio-utils in Ubuntu 22.04.'
        )

    command = [
        'parec',
        '--format=s16le',
        f'--rate={rate}',
        f'--channels={channels}',
    ]
    if source:
        command.append(f'--device={source}')

    bytes_per_sample = 2
    byte_count = int(duration * rate * channels * bytes_per_sample)
    print(
        f'Stream recording {duration:.1f}s with parec, '
        f'rate={rate}, channels={channels}, source={source or "default"}...',
        flush=True,
    )
    run_countdown(countdown)
    print(
        f'>>> START RECORDING NOW ({duration:.1f}s) <<<',
        flush=True,
    )
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    wav_file = None
    if keep_wav:
        wav_file = wave.open(str(Path(keep_wav)), 'wb')
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(bytes_per_sample)
        wav_file.setframerate(rate)

    sender.begin_stream(rate, channels)
    remaining_bytes = byte_count
    chunk_count = 0
    streamed_bytes = 0
    try:
        while remaining_bytes > 0:
            requested = min(chunk_size, remaining_bytes)
            raw_audio = process.stdout.read(requested)
            if not raw_audio:
                break
            sender.publish_chunk(raw_audio)
            if wav_file:
                wav_file.writeframesraw(raw_audio)
            remaining_bytes -= len(raw_audio)
            streamed_bytes += len(raw_audio)
            chunk_count += 1
            if publish_delay > 0:
                time.sleep(publish_delay)
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
        if wav_file:
            wav_file.close()

    print('>>> RECORDING FINISHED <<<', flush=True)

    if streamed_bytes == 0:
        raise SystemExit(
            'parec produced no audio bytes. '
            'Check WSLg audio and microphone permissions.'
        )
    sender.end_stream()
    sender.get_logger().info(
        f'audio stream complete: chunks={chunk_count}, bytes={streamed_bytes}'
    )


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            'Stream audio from WSL Ubuntu 22.04 to Android '
            'over ROS 2 Humble.'
        )
    )
    parser.add_argument(
        '--input-wav',
        help='Existing WAV file to send instead of recording.',
    )
    parser.add_argument(
        '--duration',
        type=float,
        default=3.0,
        help='Recording duration in seconds.',
    )
    parser.add_argument(
        '--countdown',
        type=int,
        default=3,
        help='Seconds to count down before recording starts.',
    )
    parser.add_argument(
        '--rate',
        type=int,
        default=16000,
        help='Recording sample rate.',
    )
    parser.add_argument(
        '--channels',
        type=int,
        default=1,
        help='Recording channel count.',
    )
    parser.add_argument(
        '--source',
        default=os.environ.get('PULSE_SOURCE', ''),
        help='PulseAudio source, such as RDPSource.',
    )
    parser.add_argument(
        '--chunk-size',
        type=int,
        default=2048,
        help='Raw PCM bytes per ROS 2 audio chunk.',
    )
    parser.add_argument(
        '--publish-delay',
        type=float,
        default=0.0,
        help='Delay between chunk publishes in seconds.',
    )
    parser.add_argument(
        '--discovery-timeout',
        type=float,
        default=8.0,
        help='Seconds to wait for Android audio subscribers before sending.',
    )
    parser.add_argument(
        '--qos',
        choices=['best_effort', 'reliable'],
        default=os.environ.get('WSL_DEMO_AUDIO_QOS', 'reliable'),
    )
    parser.add_argument(
        '--keep-wav',
        help='Optional path to keep the recorded WAV in WSL.',
    )
    return parser.parse_args()


def main():
    args = parse_args()
    rclpy.init()
    sender = AudioSender(args.qos)
    try:
        if args.input_wav:
            sender.stream_wav_file(
                args.input_wav,
                args.chunk_size,
                args.publish_delay,
                args.discovery_timeout,
            )
        else:
            sender.stream_recording(
                args.duration,
                args.rate,
                args.channels,
                args.source,
                args.chunk_size,
                args.publish_delay,
                args.discovery_timeout,
                args.countdown,
                args.keep_wav,
            )
    finally:
        sender.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
