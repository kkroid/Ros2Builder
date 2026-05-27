package com.example.ros2demo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.IBinder;

import java.io.File;

public class Ros2DemoService extends Service {
    public static final String ACTION_START = "com.example.ros2demo.START";
    public static final String ACTION_STOP = "com.example.ros2demo.STOP";
    public static final String EXTRA_DOMAIN_ID = "domainId";
    public static final String EXTRA_NODE_NAME = "nodeName";
    public static final String EXTRA_RATE_HZ = "rateHz";
    public static final String EXTRA_QOS = "qos";
    public static final String EXTRA_DISCOVERY_SERVER = "discoveryServer";
    public static final String EXTRA_AUTO_START = "autoStart";
    public static final int DEFAULT_DOMAIN_ID = 0;
    public static final String DEFAULT_NODE_NAME = "android_phone_node";
    public static final String AUDIO_FILE_NAME = "ros2_audio.wav";

    private static final String CHANNEL_ID = "ros2-demo-runtime";
    private static final int NOTIFICATION_ID = 2001;

    private WifiManager.MulticastLock multicastLock;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        acquireMulticastLock();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopSelf();
            return START_NOT_STICKY;
        }

        startForeground(NOTIFICATION_ID, buildNotification("ROS 2 runtime starting"));

        int domainId = intent == null ? DEFAULT_DOMAIN_ID : intent.getIntExtra(EXTRA_DOMAIN_ID, DEFAULT_DOMAIN_ID);
        String nodeName = intent == null ? DEFAULT_NODE_NAME : intent.getStringExtra(EXTRA_NODE_NAME);
        double rateHz = intent == null ? 1.0 : intent.getDoubleExtra(EXTRA_RATE_HZ, 1.0);
        String qos = intent == null ? "best_effort" : intent.getStringExtra(EXTRA_QOS);
        String discoveryServer = intent == null ? "" : intent.getStringExtra(EXTRA_DISCOVERY_SERVER);

        if (nodeName == null || nodeName.trim().isEmpty()) {
            nodeName = DEFAULT_NODE_NAME;
        }
        if (qos == null || qos.trim().isEmpty()) {
            qos = "best_effort";
        }
        if (discoveryServer == null) {
            discoveryServer = "";
        }

        File audioFile = new File(getFilesDir(), AUDIO_FILE_NAME);
        boolean started = NativeRosBridge.startSession(
            domainId,
            nodeName,
            rateHz,
            qos,
            discoveryServer.trim(),
            audioFile.getAbsolutePath()
        );
        startForeground(
            NOTIFICATION_ID,
            buildNotification(started ? "ROS 2 runtime active" : "ROS 2 runtime failed")
        );
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        NativeRosBridge.stopSession();
        releaseMulticastLock();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void acquireMulticastLock() {
        WifiManager wifiManager = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifiManager == null) {
            return;
        }
        multicastLock = wifiManager.createMulticastLock("ros2-demo-multicast");
        multicastLock.setReferenceCounted(false);
        multicastLock.acquire();
    }

    private void releaseMulticastLock() {
        if (multicastLock != null && multicastLock.isHeld()) {
            multicastLock.release();
        }
        multicastLock = null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "ROS 2 runtime",
                NotificationManager.IMPORTANCE_LOW
        );
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager != null) {
            manager.createNotificationChannel(channel);
        }
    }

    private Notification buildNotification(String text) {
        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        return builder
                .setContentTitle("ROS 2 Android Demo")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_upload_done)
                .setOngoing(true)
                .build();
    }
}