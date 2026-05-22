#!/usr/bin/env python3
import os
import time
from collections import deque

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


class WslAndroidPeer(Node):
    def __init__(self):
        super().__init__('wsl_humble_android_peer')
        self.status_topic = os.environ.get(
            'ANDROID_STATUS_TOPIC',
            '/android/status',
        )
        self.command_topic = os.environ.get(
            'ANDROID_COMMAND_TOPIC',
            '/android/command',
        )
        self.command_period = float(
            os.environ.get('WSL_DEMO_COMMAND_PERIOD', '5.0')
        )
        self.exit_after = float(os.environ.get('WSL_DEMO_EXIT_AFTER', '0'))
        self.commands = self._parse_commands(
            os.environ.get('WSL_DEMO_COMMANDS', 'ping')
        )
        self.qos_mode = os.environ.get('WSL_DEMO_QOS', 'best_effort')
        qos = self._make_qos(self.qos_mode)

        self.started_at = time.monotonic()
        self.status_count = 0
        self.command_count = 0
        self.command_index = 0
        self.should_stop = False
        self.last_status_at = None
        self.last_status = ''
        self.recent_status = deque(maxlen=5)

        self.status_subscription = self.create_subscription(
            String,
            self.status_topic,
            self.on_status,
            qos,
        )
        self.command_publisher = self.create_publisher(
            String,
            self.command_topic,
            qos,
        )
        self.command_timer = self.create_timer(
            self.command_period,
            self.publish_command,
        )
        self.report_timer = self.create_timer(2.0, self.report)
        if self.exit_after > 0:
            self.exit_timer = self.create_timer(self.exit_after, self.stop)
        else:
            self.exit_timer = None

        self.get_logger().info(
            'WSL Humble peer started: '
            f'subscribe={self.status_topic}, '
            f'publish={self.command_topic}, '
            f'qos={self.qos_mode}'
        )
        if self.exit_after > 0:
            self.get_logger().info(f'Auto-exit after {self.exit_after}s')

    def _make_qos(self, qos_mode):
        qos = QoSProfile(depth=10)
        if qos_mode == 'reliable':
            qos.reliability = ReliabilityPolicy.RELIABLE
        else:
            qos.reliability = ReliabilityPolicy.BEST_EFFORT
        return qos

    def _parse_commands(self, raw_value):
        commands = [
            command.strip()
            for command in raw_value.split(',')
            if command.strip()
        ]
        return commands or ['ping']

    def on_status(self, message):
        self.status_count += 1
        self.last_status_at = time.monotonic()
        self.last_status = message.data
        self.recent_status.append(message.data)

    def publish_command(self):
        command = self.commands[self.command_index % len(self.commands)]
        self.command_index += 1
        message = String()
        message.data = command
        self.command_publisher.publish(message)
        self.command_count += 1
        self.get_logger().info(
            f'published command #{self.command_count}: {command}'
        )

    def report(self):
        elapsed = max(time.monotonic() - self.started_at, 0.001)
        rate = self.status_count / elapsed
        if self.last_status_at is None:
            age = 'never'
        else:
            age = f'{time.monotonic() - self.last_status_at:.1f}s ago'
        self.get_logger().info(
            f'status_count={self.status_count} '
            f'avg_rate={rate:.2f}Hz last_status={age}'
        )
        if self.last_status:
            self.get_logger().info(f'last Android status: {self.last_status}')

    def stop(self):
        self.get_logger().info('auto-exit requested')
        self.should_stop = True


def main():
    rclpy.init()
    node = WslAndroidPeer()
    try:
        while rclpy.ok() and not node.should_stop:
            rclpy.spin_once(node, timeout_sec=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
