package com.example.ros2demo;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.io.IOException;

public class MainActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView statusView;
    private EditText domainInput;
    private EditText nodeInput;
    private EditText rateInput;
    private EditText commandInput;
    private TextView audioSizeView;
    private boolean polling;
    private MediaPlayer mediaPlayer;
    private AudioTrack audioTrack;
    private Thread audioPlaybackThread;
    private volatile boolean audioPlaybackRunning;
    private long lastAudioFileLength = -1;
    private long lastAudioFileModified = -1;

    private final Runnable pollSnapshot = new Runnable() {
        @Override
        public void run() {
            if (!polling) {
                return;
            }
            statusView.setText(NativeRosBridge.getSnapshotJson());
            updateAudioSize();
            handler.postDelayed(this, 1000);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestRuntimePermissions();
        setContentView(buildContentView());
    }

    @Override
    protected void onStart() {
        super.onStart();
        polling = true;
        startStreamingPlayback();
        pollSnapshot.run();
    }

    @Override
    protected void onStop() {
        polling = false;
        handler.removeCallbacks(pollSnapshot);
        stopStreamingPlayback();
        super.onStop();
    }

    private ScrollView buildContentView() {
        int padding = dp(16);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(padding, padding, padding, padding);

        TextView title = new TextView(this);
        title.setText("ROS 2 Android Demo");
        title.setTextSize(24);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title, matchWrap());

        TextView subtitle = new TextView(this);
        subtitle.setText("C++ owns ROS 2 runtime. Java renders state only.");
        subtitle.setTextSize(14);
        subtitle.setPadding(0, dp(4), 0, dp(12));
        root.addView(subtitle, matchWrap());

        domainInput = input(String.valueOf(Ros2DemoService.DEFAULT_DOMAIN_ID));
        nodeInput = input(Ros2DemoService.DEFAULT_NODE_NAME);
        rateInput = input("1.0");
        commandInput = input("ping");

        root.addView(label("ROS_DOMAIN_ID"));
        root.addView(domainInput, matchWrap());
        root.addView(label("Node name"));
        root.addView(nodeInput, matchWrap());
        root.addView(label("Publish rate Hz"));
        root.addView(rateInput, matchWrap());

        LinearLayout controls = new LinearLayout(this);
        controls.setGravity(Gravity.CENTER_VERTICAL);
        controls.setPadding(0, dp(12), 0, dp(12));

        Button start = new Button(this);
        start.setText("Start");
        start.setOnClickListener(view -> startRuntime());
        controls.addView(start, weightedButton());

        Button stop = new Button(this);
        stop.setText("Stop");
        stop.setOnClickListener(view -> stopRuntime());
        controls.addView(stop, weightedButton());
        root.addView(controls, matchWrap());

        root.addView(label("Local command"));
        root.addView(commandInput, matchWrap());

        Button sendCommand = new Button(this);
        sendCommand.setText("Send to C++ Core");
        sendCommand.setOnClickListener(view -> NativeRosBridge.sendUserCommand(commandInput.getText().toString()));
        root.addView(sendCommand, matchWrap());

        audioSizeView = new TextView(this);
        audioSizeView.setTextSize(14);
        audioSizeView.setPadding(0, dp(12), 0, dp(4));
        root.addView(audioSizeView, matchWrap());

        Button playAudio = new Button(this);
        playAudio.setText("Play Received Audio");
        playAudio.setOnClickListener(view -> playReceivedAudio());
        root.addView(playAudio, matchWrap());

        statusView = new TextView(this);
        statusView.setTextSize(13);
        statusView.setTypeface(Typeface.MONOSPACE);
        statusView.setText("{}");
        statusView.setPadding(0, dp(12), 0, 0);
        root.addView(statusView, matchWrap());

        ScrollView scrollView = new ScrollView(this);
        scrollView.addView(root);
        return scrollView;
    }

    private void startRuntime() {
        String nodeName = nodeInput.getText().toString().trim();
        if (!isValidNodeName(nodeName)) {
            String message = "Invalid node name. Use letters, numbers and '_' only; do not include '/'. Example: "
                    + Ros2DemoService.DEFAULT_NODE_NAME;
            nodeInput.setError(message);
            statusView.setText(message);
            return;
        }

        Intent intent = new Intent(this, Ros2DemoService.class);
        intent.setAction(Ros2DemoService.ACTION_START);
        intent.putExtra(
            Ros2DemoService.EXTRA_DOMAIN_ID,
            parseInt(domainInput.getText().toString(), Ros2DemoService.DEFAULT_DOMAIN_ID)
        );
        intent.putExtra(Ros2DemoService.EXTRA_NODE_NAME, nodeName);
        intent.putExtra(Ros2DemoService.EXTRA_RATE_HZ, parseDouble(rateInput.getText().toString(), 1.0));
        intent.putExtra(Ros2DemoService.EXTRA_QOS, "best_effort");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent);
        } else {
            startService(intent);
        }
    }

    private void stopRuntime() {
        Intent intent = new Intent(this, Ros2DemoService.class);
        intent.setAction(Ros2DemoService.ACTION_STOP);
        startService(intent);
    }

    private void updateAudioSize() {
        File audioFile = getAudioFile();
        long fileLength = audioFile.length();
        long fileModified = audioFile.lastModified();
        if (lastAudioFileLength >= 0
                && (fileLength != lastAudioFileLength || fileModified != lastAudioFileModified)) {
            releaseMediaPlayer();
        }
        lastAudioFileLength = fileLength;
        lastAudioFileModified = fileModified;

        long size = Math.max(fileLength, NativeRosBridge.getAudioFileSize());
        audioSizeView.setText("Received audio file: " + size + " bytes");
    }

    private void playReceivedAudio() {
        File audioFile = getAudioFile();
        if (!audioFile.exists() || audioFile.length() <= 0) {
            audioSizeView.setText("Received audio file: 0 bytes");
            return;
        }
        try {
            releaseMediaPlayer();
            mediaPlayer = new MediaPlayer();
            mediaPlayer.setDataSource(audioFile.getAbsolutePath());
            mediaPlayer.setOnCompletionListener(player -> {
                player.release();
                if (mediaPlayer == player) {
                    mediaPlayer = null;
                }
            });
            mediaPlayer.prepare();
            mediaPlayer.start();
        } catch (IOException | RuntimeException error) {
            audioSizeView.setText("Audio playback failed: " + error.getMessage());
        }
    }

    private File getAudioFile() {
        return new File(getFilesDir(), Ros2DemoService.AUDIO_FILE_NAME);
    }

    @Override
    protected void onDestroy() {
        releaseMediaPlayer();
        super.onDestroy();
    }

    private void releaseMediaPlayer() {
        if (mediaPlayer != null) {
            mediaPlayer.release();
            mediaPlayer = null;
        }
    }

    private void startStreamingPlayback() {
        if (audioPlaybackRunning) {
            return;
        }
        audioPlaybackRunning = true;
        audioPlaybackThread = new Thread(this::playStreamingAudio, "ros2-audio-playback");
        audioPlaybackThread.start();
    }

    private void stopStreamingPlayback() {
        audioPlaybackRunning = false;
        if (audioPlaybackThread != null) {
            audioPlaybackThread.interrupt();
            try {
                audioPlaybackThread.join(1000);
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
            }
            audioPlaybackThread = null;
        }
        releaseAudioTrack();
    }

    private void playStreamingAudio() {
        while (audioPlaybackRunning) {
            byte[] data = NativeRosBridge.drainAudioPcm();
            if (data.length > 0) {
                releaseMediaPlayer();
                ensureAudioTrack();
                audioTrack.write(data, 0, data.length);
            } else {
                try {
                    Thread.sleep(20);
                } catch (InterruptedException error) {
                    Thread.currentThread().interrupt();
                    return;
                }
            }
        }
    }

    private void ensureAudioTrack() {
        if (audioTrack != null) {
            return;
        }
        int minBufferSize = AudioTrack.getMinBufferSize(
                16000,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT);
        int bufferSize = Math.max(minBufferSize, 8192);
        audioTrack = new AudioTrack(
                AudioManager.STREAM_MUSIC,
                16000,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
                AudioTrack.MODE_STREAM);
        audioTrack.play();
    }

    private void releaseAudioTrack() {
        if (audioTrack != null) {
            audioTrack.stop();
            audioTrack.release();
            audioTrack = null;
        }
    }

    private void requestRuntimePermissions() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1001);
        }
    }

    private TextView label(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setPadding(0, dp(10), 0, dp(4));
        return view;
    }

    private EditText input(String text) {
        EditText editText = new EditText(this);
        editText.setSingleLine(true);
        editText.setText(text);
        return editText;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private LinearLayout.LayoutParams weightedButton() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        params.setMargins(dp(4), 0, dp(4), 0);
        return params;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private int parseInt(String text, int fallback) {
        try {
            return Integer.parseInt(text.trim());
        } catch (RuntimeException ignored) {
            return fallback;
        }
    }

    private double parseDouble(String text, double fallback) {
        try {
            return Double.parseDouble(text.trim());
        } catch (RuntimeException ignored) {
            return fallback;
        }
    }

    private boolean isValidNodeName(String text) {
        return text.matches("[A-Za-z_][A-Za-z0-9_]*");
    }
}