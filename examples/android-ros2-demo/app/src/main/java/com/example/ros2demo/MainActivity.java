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
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public class MainActivity extends Activity {
    private static final String TAG = "Ros2DemoApp";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView statusView;
    private EditText domainInput;
    private EditText nodeInput;
    private EditText rateInput;
    private EditText discoveryInput;
    private EditText commandInput;
    private TextView audioSizeView;
    private boolean polling;
    private MediaPlayer mediaPlayer;
    private AudioTrack audioTrack;
    private Thread audioPlaybackThread;
    private volatile boolean audioPlaybackRunning;
    private long lastAudioFileLength = -1;
    private long lastAudioFileModified = -1;
    private TextView txAudioView;
    private Thread txAudioThread;
    private volatile boolean txAudioRunning;
    private volatile double txAudioSpeed = 1.0;
    private int txAudioRequestId;
    private static final int REQUEST_PICK_AUDIO = 2001;
    private static final String EXTRA_SEND_AUDIO_FILE = "sendAudioFile";
    private static final String EXTRA_SEND_SPEED = "sendSpeed";

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
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntentAudioSend(intent);
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
        discoveryInput = input(getIntent().getStringExtra(Ros2DemoService.EXTRA_DISCOVERY_SERVER));
        commandInput = input("ping");

        root.addView(label("ROS_DOMAIN_ID"));
        root.addView(domainInput, matchWrap());
        root.addView(label("Node name"));
        root.addView(nodeInput, matchWrap());
        root.addView(label("Publish rate Hz"));
        root.addView(rateInput, matchWrap());
        root.addView(label("ROS_DISCOVERY_SERVER"));
        root.addView(discoveryInput, matchWrap());

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

        txAudioView = new TextView(this);
        txAudioView.setTextSize(14);
        txAudioView.setPadding(0, dp(12), 0, dp(4));
        txAudioView.setText("Send to PC: idle");
        root.addView(txAudioView, matchWrap());

        LinearLayout txButtons = new LinearLayout(this);
        Button pickAudio = new Button(this);
        pickAudio.setText("Send Audio File to PC");
        pickAudio.setOnClickListener(view -> pickAudioFile());
        txButtons.addView(pickAudio, weightedButton());

        Button cancelTx = new Button(this);
        cancelTx.setText("Cancel Send");
        cancelTx.setOnClickListener(view -> cancelTxAudio());
        txButtons.addView(cancelTx, weightedButton());
        root.addView(txButtons, matchWrap());

        statusView = new TextView(this);
        statusView.setTextSize(13);
        statusView.setTypeface(Typeface.MONOSPACE);
        statusView.setText("{}");
        statusView.setPadding(0, dp(12), 0, 0);
        root.addView(statusView, matchWrap());

        ScrollView scrollView = new ScrollView(this);
        scrollView.addView(root);

        if (getIntent().getBooleanExtra(Ros2DemoService.EXTRA_AUTO_START, false)) {
            handler.post(this::startRuntime);
        }
        handleIntentAudioSend(getIntent());
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
        intent.putExtra(Ros2DemoService.EXTRA_DISCOVERY_SERVER, discoveryInput.getText().toString().trim());
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
        cancelTxAudio();
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

    // ----- Streaming audio from phone to PC -----

    private void pickAudioFile() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("audio/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"audio/wav", "audio/x-wav", "audio/*"});
        startActivityForResult(intent, REQUEST_PICK_AUDIO);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_PICK_AUDIO && resultCode == Activity.RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri != null) {
                startTxAudio(uri);
            }
        }
    }

    private void cancelTxAudio() {
        txAudioRequestId++;
        txAudioRunning = false;
        if (txAudioThread != null) {
            txAudioThread.interrupt();
            txAudioThread = null;
        }
    }

    private void startTxAudio(Uri uri) {
        cancelTxAudio();
        int requestId = ++txAudioRequestId;
        txAudioView.setText("Send to PC: starting ROS session...");
        startRuntime();
        handler.postDelayed(() -> {
            if (requestId != txAudioRequestId) {
                return;
            }
            txAudioRunning = true;
            txAudioView.setText("Send to PC: reading file...");
            txAudioThread = new Thread(() -> sendAudioFile(uri), "ros2-audio-tx");
            txAudioThread.start();
        }, 3000);
    }

    private void handleIntentAudioSend(Intent intent) {
        if (intent == null) {
            return;
        }
        String path = intent.getStringExtra(EXTRA_SEND_AUDIO_FILE);
        if (path == null || path.trim().isEmpty()) {
            return;
        }
        txAudioSpeed = parseSendSpeed(intent);
        Log.i(TAG, "auto send audio file: " + path.trim());
        handler.post(() -> startTxAudio(Uri.fromFile(new File(path.trim()))));
    }

    private void sendAudioFile(Uri uri) {
        try {
            byte[] all = readAll(uri);
            WavInfo info = parseWav(all);
            Log.i(TAG, "send audio loaded uri=" + uri + " bytes=" + all.length
                    + " rate=" + info.rate + " channels=" + info.channels + " width=" + info.width
                    + " pcm=" + info.pcm.length + " speed=" + txAudioSpeed);
            postTx("loaded " + all.length + " bytes, "
                    + info.rate + "Hz/" + info.channels + "ch/" + info.width + "B "
                    + "(" + info.pcm.length + " PCM bytes), speed=" + txAudioSpeed + "x");

            if (!NativeRosBridge.publishTxAudioControl(
                    "begin_stream:" + info.rate + ":" + info.channels + ":" + info.width)) {
                Log.w(TAG, "send audio publish begin_stream failed");
                postTx("FAILED: publish control (session not running?)");
                return;
            }
            // give subscriber a moment to flip state
            Thread.sleep(200);

            final int chunkMs = 100;
            final int bytesPerSample = info.channels * info.width;
            final int samplesPerChunk = Math.max(1, info.rate * chunkMs / 1000);
            final int chunkBytes = samplesPerChunk * bytesPerSample;
            final double speed = Math.max(1.0, txAudioSpeed);
            final long periodNanos = (long) (chunkMs * 1_000_000L / speed);

            int sent = 0;
            int total = info.pcm.length;
            int chunks = 0;
            long nextDeadline = System.nanoTime();
            while (txAudioRunning && sent < total) {
                int end = Math.min(sent + chunkBytes, total);
                byte[] slice = new byte[end - sent];
                System.arraycopy(info.pcm, sent, slice, 0, slice.length);
                if (!NativeRosBridge.publishTxAudioChunk(slice)) {
                    Log.w(TAG, "send audio publish chunk failed at " + sent + " bytes");
                    postTx("FAILED: publish chunk at " + sent + " bytes");
                    return;
                }
                sent = end;
                chunks++;
                if (chunks % 10 == 0) {
                    int progress = (int) (sent * 100L / Math.max(1, total));
                    postTx("sending " + sent + "/" + total + " bytes (" + progress + "%) chunks=" + chunks);
                }
                nextDeadline += periodNanos;
                long sleep = nextDeadline - System.nanoTime();
                if (periodNanos > 0 && sleep > 0) {
                    Thread.sleep(sleep / 1_000_000L, (int) (sleep % 1_000_000L));
                } else {
                    nextDeadline = System.nanoTime();
                }
            }
            Thread.sleep(200);
            NativeRosBridge.publishTxAudioControl("end_stream");
            Log.i(TAG, "send audio done sent=" + sent + " total=" + total + " chunks=" + chunks);
            postTx("done: sent " + sent + "/" + total + " bytes in " + chunks + " chunks");
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            NativeRosBridge.publishTxAudioControl("end_stream");
            Log.i(TAG, "send audio cancelled");
            postTx("cancelled");
        } catch (Exception error) {
            Log.e(TAG, "send audio failed", error);
            postTx("FAILED: " + error.getClass().getSimpleName() + ": " + error.getMessage());
        } finally {
            txAudioRunning = false;
        }
    }

    private double parseSendSpeed(Intent intent) {
        Bundle extras = intent.getExtras();
        if (extras == null || !extras.containsKey(EXTRA_SEND_SPEED)) {
            return 1.0;
        }
        Object value = extras.get(EXTRA_SEND_SPEED);
        try {
            if (value instanceof Number) {
                return Math.max(1.0, ((Number) value).doubleValue());
            }
            if (value instanceof String) {
                return Math.max(1.0, Double.parseDouble(((String) value).trim()));
            }
        } catch (RuntimeException ignored) {
            return 1.0;
        }
        return 1.0;
    }

    private void postTx(String text) {
        handler.post(() -> txAudioView.setText("Send to PC: " + text));
    }

    private byte[] readAll(Uri uri) throws IOException {
        InputStream stream;
        if ("file".equals(uri.getScheme()) || uri.getScheme() == null) {
            stream = new FileInputStream(new File(uri.getPath()));
        } else {
            stream = getContentResolver().openInputStream(uri);
        }
        try (InputStream input = stream) {
            if (input == null) {
                throw new IOException("cannot open URI");
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream(64 * 1024);
            byte[] buf = new byte[8192];
            int n;
            while ((n = input.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return out.toByteArray();
        }
    }

    private static final class WavInfo {
        final int rate;
        final int channels;
        final int width;
        final byte[] pcm;
        WavInfo(int rate, int channels, int width, byte[] pcm) {
            this.rate = rate;
            this.channels = channels;
            this.width = width;
            this.pcm = pcm;
        }
    }

    /**
     * Minimal RIFF/WAVE parser. Accepts a top-level RIFF/WAVE with a single
     * fmt chunk (PCM, format=1) and a single data chunk. Throws on anything else.
     */
    private static WavInfo parseWav(byte[] data) throws IOException {
        if (data.length < 44) {
            throw new IOException("file too small to be WAV");
        }
        ByteBuffer bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
        if (data[0] != 'R' || data[1] != 'I' || data[2] != 'F' || data[3] != 'F') {
            throw new IOException("not a RIFF file");
        }
        if (data[8] != 'W' || data[9] != 'A' || data[10] != 'V' || data[11] != 'E') {
            throw new IOException("not a WAVE file");
        }
        int pos = 12;
        int rate = 0;
        int channels = 0;
        int width = 0;
        byte[] pcm = null;
        while (pos + 8 <= data.length) {
            String id = new String(data, pos, 4);
            int size = bb.getInt(pos + 4);
            int payload = pos + 8;
            if (size < 0 || payload + size > data.length) {
                size = data.length - payload;
            }
            if ("fmt ".equals(id)) {
                short format = bb.getShort(payload);
                if (format != 1) {
                    throw new IOException("only PCM WAV supported (format=" + format + ")");
                }
                channels = bb.getShort(payload + 2) & 0xffff;
                rate = bb.getInt(payload + 4);
                short bitsPerSample = bb.getShort(payload + 14);
                width = (bitsPerSample & 0xffff) / 8;
            } else if ("data".equals(id)) {
                pcm = new byte[size];
                System.arraycopy(data, payload, pcm, 0, size);
                break;
            }
            pos = payload + size + (size & 1); // chunks are word-aligned
        }
        if (rate <= 0 || channels <= 0 || width <= 0 || pcm == null) {
            throw new IOException("missing fmt/data chunk");
        }
        return new WavInfo(rate, channels, width, pcm);
    }
}