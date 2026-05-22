#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import tempfile
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
        super().__init__('pc_audio_sender')
        qos = self._make_qos(qos_mode)
        self.control_publisher = self.create_publisher(
            String,
            os.environ.get('ANDROID_AUDIO_CONTROL_TOPIC', '/android/audio_control'),
            qos,
        )
        self.chunk_publisher = self.create_publisher(
            UInt8MultiArray,
            os.environ.get('ANDROID_AUDIO_CHUNK_TOPIC', '/android/audio_chunk'),
            qos,
        )

    def _make_qos(self, qos_mode):
        qos = QoSProfile(depth=10)
        if qos_mode == 'reliable':
            qos.reliability = ReliabilityPolicy.RELIABLE
        else:
            qos.reliability = ReliabilityPolicy.BEST_EFFORT
        return qos

    def send_file(self, wav_path, chunk_size, publish_delay):
        wav_path = Path(wav_path)
        size = wav_path.stat().st_size
        self.get_logger().info(f'sending {wav_path} ({size} bytes)')

        control = String()
        control.data = 'begin'
        self.control_publisher.publish(control)
        rclpy.spin_once(self, timeout_sec=0.2)
        time.sleep(0.4)

        chunk_count = 0
        with wav_path.open('rb') as audio_file:
            while True:
                chunk = audio_file.read(chunk_size)
                if not chunk:
                    break
                message = UInt8MultiArray()
                message.data = array('B', chunk)
                self.chunk_publisher.publish(message)
                chunk_count += 1
                rclpy.spin_once(self, timeout_sec=0)
                if publish_delay > 0:
                    time.sleep(publish_delay)

        time.sleep(0.2)
        control.data = 'end'
        self.control_publisher.publish(control)
        rclpy.spin_once(self, timeout_sec=0.2)
        self.get_logger().info(f'audio transfer complete: chunks={chunk_count}, bytes={size}')


def record_wav_sounddevice(output_path, duration, rate, channels):
    try:
        import sounddevice as sounddevice
    except ImportError as error:
        raise SystemExit(
            'Recording requires the sounddevice package. Install it in this ROS 2 Python environment, '
            'or pass --input-wav to stream an existing WAV file.'
        ) from error

    frames = int(duration * rate)
    print(f'Recording {duration:.1f}s, rate={rate}, channels={channels}...')
    recording = sounddevice.rec(frames, samplerate=rate, channels=channels, dtype='int16')
    sounddevice.wait()

    with wave.open(str(output_path), 'wb') as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(rate)
        wav_file.writeframes(recording.tobytes())


def record_wav_parec(output_path, duration, rate, channels, source):
    if shutil.which('parec') is None:
        raise SystemExit('Recording with --backend parec requires the parec command from pulseaudio-utils.')

    command = [
        'parec',
        f'--format=s16le',
        f'--rate={rate}',
        f'--channels={channels}',
    ]
    if source:
        command.append(f'--device={source}')

    byte_count = int(duration * rate * channels * 2)
    print(f'Recording {duration:.1f}s with parec, rate={rate}, channels={channels}, source={source or "default"}...')
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    try:
        raw_audio = process.stdout.read(byte_count)
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()

    if len(raw_audio) == 0:
        raise SystemExit('parec produced no audio bytes. Check PULSE_SERVER, microphone permissions and the selected source.')

    with wave.open(str(output_path), 'wb') as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(rate)
        wav_file.writeframes(raw_audio)


def record_wav(output_path, duration, rate, channels, backend, source):
    if backend == 'parec':
        record_wav_parec(output_path, duration, rate, channels, source)
    elif backend == 'sounddevice':
        record_wav_sounddevice(output_path, duration, rate, channels)
    else:
        if shutil.which('parec') is not None and os.environ.get('PULSE_SERVER'):
            record_wav_parec(output_path, duration, rate, channels, source)
        else:
            record_wav_sounddevice(output_path, duration, rate, channels)


def parse_args():
    parser = argparse.ArgumentParser(description='Record or stream a WAV file to the Android ROS 2 demo.')
    parser.add_argument('--input-wav', help='Existing WAV file to stream instead of recording from the microphone.')
    parser.add_argument('--duration', type=float, default=3.0, help='Recording duration in seconds.')
    parser.add_argument('--rate', type=int, default=16000, help='Recording sample rate.')
    parser.add_argument('--channels', type=int, default=1, help='Recording channel count.')
    parser.add_argument('--backend', choices=['auto', 'sounddevice', 'parec'], default='auto', help='Recording backend.')
    parser.add_argument('--source', default=os.environ.get('PULSE_SOURCE', ''), help='PulseAudio source name for --backend parec.')
    parser.add_argument('--chunk-size', type=int, default=8192, help='Bytes per ROS 2 audio chunk.')
    parser.add_argument('--publish-delay', type=float, default=0.01, help='Delay between chunk publishes in seconds.')
    parser.add_argument('--qos', choices=['best_effort', 'reliable'], default=os.environ.get('ROS2_AUDIO_QOS', 'reliable'))
    parser.add_argument('--keep-wav', help='Optional path to keep the recorded WAV on the PC.')
    return parser.parse_args()


def main():
    args = parse_args()
    if args.input_wav:
        wav_path = Path(args.input_wav)
    else:
        if args.keep_wav:
            wav_path = Path(args.keep_wav)
        else:
            temp_file = tempfile.NamedTemporaryFile(prefix='ros2_android_audio_', suffix='.wav', delete=False)
            temp_file.close()
            wav_path = Path(temp_file.name)
        record_wav(wav_path, args.duration, args.rate, args.channels, args.backend, args.source)

    rclpy.init()
    sender = AudioSender(args.qos)
    try:
        sender.send_file(wav_path, args.chunk_size, args.publish_delay)
    finally:
        sender.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
