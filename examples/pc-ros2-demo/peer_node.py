#!/usr/bin/env python3
import os
import time
from collections import deque

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy
from std_msgs.msg import String


class AndroidPeerNode(Node):
    def __init__(self):
        super().__init__('pc_demo_peer')

        self.status_topic = os.environ.get(
            'ANDROID_STATUS_TOPIC',
            '/android/status',
        )
        self.command_topic = os.environ.get(
            'ANDROID_COMMAND_TOPIC',
            '/android/command',
        )
        self.command_period = float(
            os.environ.get('ROS2_PEER_COMMAND_PERIOD', '5.0')
        )
        self.exit_after = float(os.environ.get('ROS2_PEER_EXIT_AFTER', '0'))
        self.qos_mode = os.environ.get('ROS2_PEER_QOS', 'best_effort')
        self.commands = self._parse_commands(
            os.environ.get('ROS2_PEER_COMMANDS', 'ping')
        )
        qos = self._make_qos(self.qos_mode)

        self.status_count = 0
        self.command_count = 0
        self.started_at = time.monotonic()
        self.last_status_at = None
        self.last_status = ''
        self.recent_status = deque(maxlen=5)
        self.command_index = 0

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
            'PC ROS 2 peer started. '
            f'Subscribing {self.status_topic}, publishing {self.command_topic}'
        )
        self.get_logger().info(
            f'Command loop: {self.commands}, period={self.command_period}s, qos={self.qos_mode}'
        )
        if self.exit_after > 0:
            self.get_logger().info(f'Auto-exit after {self.exit_after}s')

    def _parse_commands(self, raw_value):
        commands = [
            command.strip()
            for command in raw_value.split(',')
            if command.strip()
        ]
        return commands or ['ping']

    def _make_qos(self, qos_mode):
        qos = QoSProfile(depth=10)
        if qos_mode == 'reliable':
            qos.reliability = ReliabilityPolicy.RELIABLE
        else:
            qos.reliability = ReliabilityPolicy.BEST_EFFORT
        return qos

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
        if rclpy.ok():
            rclpy.shutdown()


def main():
    rclpy.init()
    node = AndroidPeerNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
