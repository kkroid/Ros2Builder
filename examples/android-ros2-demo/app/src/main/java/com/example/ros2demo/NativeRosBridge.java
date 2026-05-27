package com.example.ros2demo;

public final class NativeRosBridge {
    static {
        System.loadLibrary("ros2_android_demo");
    }

    private NativeRosBridge() {
    }

    public static native boolean startSession(
        int domainId,
        String nodeName,
        double publishRateHz,
        String qosMode,
        String discoveryServer,
        String audioFilePath
    );

    public static native void stopSession();

    public static native boolean sendUserCommand(String command);

    public static native String getSnapshotJson();

    public static native long getAudioFileSize();

    public static native byte[] drainAudioPcm();

    public static native boolean publishTxAudioControl(String command);

    public static native boolean publishTxAudioChunk(byte[] data);
}