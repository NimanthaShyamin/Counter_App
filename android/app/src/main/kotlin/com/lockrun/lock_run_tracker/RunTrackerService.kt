package com.lockrun.lock_run_tracker

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.VolumeProviderCompat
import androidx.media.app.NotificationCompat.MediaStyle
import io.flutter.plugin.common.MethodChannel

class RunTrackerService : Service() {

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var volumeProvider: VolumeProviderCompat
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var silentAudioTrack: AudioTrack? = null
    private var lastVolumeAdjustTime: Long = 0L
    private val VOLUME_DEBOUNCE_MS = 250L

    private val tickerRunnable = object : Runnable {
        override fun run() {
            if (isRunning) {
                totalSeconds++
                currentLapSeconds++
                updateMetadata()
                updateNotification()
                dispatchTickToFlutter()
                handler.postDelayed(this, 1000)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        initMediaSession()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> toggleTimer()
            ACTION_LAP -> triggerLap()
            ACTION_PREV -> deleteLastLap()
            ACTION_TOGGLE_LOCK -> toggleVolumeLock()
            ACTION_STOP -> {
                finishRun()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    private fun initMediaSession() {
        mediaSession = MediaSessionCompat(this, "LockRunTrackerSession")
        mediaSession.setFlags(
            MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
            MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
        )

        // VolumeProvider for hardware volume button hijacking on lock screen
        volumeProvider = object : VolumeProviderCompat(VolumeProviderCompat.VOLUME_CONTROL_RELATIVE, 100, 50) {
            override fun onAdjustVolume(direction: Int) {
                // If MainActivity is visible (either unlocked or showing over lock screen),
                // MainActivity.dispatchKeyEvent intercepts the key directly with zero latency.
                // Ignore here to completely prevent double-counting.
                if (MainActivity.isActivityVisible) {
                    return
                }

                if (isVolumeLocked) {
                    val now = System.currentTimeMillis()
                    if (now - lastVolumeAdjustTime > VOLUME_DEBOUNCE_MS) {
                        lastVolumeAdjustTime = now
                        handler.post {
                            if (direction > 0) {
                                // Volume UP -> Add Lap (auto-start if idle)
                                if (!isRunning) {
                                    startTimer()
                                }
                                triggerLap()
                            } else if (direction < 0) {
                                // Volume DOWN -> Remove / Undo Lap
                                deleteLastLap()
                            }
                        }
                    }
                }
            }
        }

        applyVolumeInterceptionMode()

        mediaSession.setCallback(object : MediaSessionCompat.Callback() {
            override fun onPlay() {
                startTimer()
            }

            override fun onPause() {
                pauseTimer()
            }

            override fun onSkipToNext() {
                // Next action triggers a Lap
                triggerLap()
            }

            override fun onSkipToPrevious() {
                // Previous button deletes the last recorded lap and backs 1 in lap count
                deleteLastLap()
            }

            override fun onCustomAction(action: String?, extras: android.os.Bundle?) {
                if (action == ACTION_TOGGLE_LOCK) {
                    toggleVolumeLock()
                }
            }
        })

        mediaSession.isActive = true
        updateMetadata()
        updatePlaybackState()
    }

    private fun applyVolumeInterceptionMode() {
        if (isVolumeLocked) {
            mediaSession.setPlaybackToRemote(volumeProvider)
        } else {
            mediaSession.setPlaybackToLocal(AudioManager.STREAM_MUSIC)
        }
    }

    private fun updatePlaybackState() {
        val stateBuilder = PlaybackStateCompat.Builder()
            .setActions(
                PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
            )
            .addCustomAction(
                PlaybackStateCompat.CustomAction.Builder(
                    ACTION_TOGGLE_LOCK,
                    if (isVolumeLocked) "Unlock Volume" else "Lock Vol to Lap",
                    if (isVolumeLocked) R.drawable.ic_media_lock else R.drawable.ic_media_unlock
                ).build()
            )
            .setState(
                if (isRunning) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                totalSeconds * 1000L,
                if (isRunning) 1.0f else 0.0f
            )
        mediaSession.setPlaybackState(stateBuilder.build())
    }

    private fun updateMetadata() {
        val lapNum = laps.size
        val lapTimeStr = formatSeconds(currentLapSeconds)
        val totalTimeStr = formatSeconds(totalSeconds)
        val lockStatusStr = if (isVolumeLocked) "🔒 VOL=LAP" else "🔊 VOL=NORMAL"

        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, "🚩 LAP $lapNum  •  $lapTimeStr")
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, "Total: $totalTimeStr  •  [$lockStatusStr]")
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, "Lock Run Tracker")
            .build()
        mediaSession.setMetadata(metadata)
    }

    private fun buildNotification(): Notification {
        val lapNum = laps.size
        val lapTimeStr = formatSeconds(currentLapSeconds)
        val totalTimeStr = formatSeconds(totalSeconds)
        val lockStatusStr = if (isVolumeLocked) "🔒 Vol=Lap" else "🔊 Vol=Normal"

        val playPauseIcon = if (isRunning) R.drawable.ic_media_pause else R.drawable.ic_media_play
        val playPauseTitle = if (isRunning) "Pause" else "Play"

        val prevPendingIntent = createPendingIntent(ACTION_PREV)
        val playPausePendingIntent = createPendingIntent(ACTION_PLAY_PAUSE)
        val lapPendingIntent = createPendingIntent(ACTION_LAP)
        val toggleLockPendingIntent = createPendingIntent(ACTION_TOGGLE_LOCK)

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val lockIcon = if (isVolumeLocked) R.drawable.ic_media_lock else R.drawable.ic_media_unlock
        val lockTitle = if (isVolumeLocked) "Locked" else "Unlocked"

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_run)
            .setContentTitle("🚩 LAP $lapNum  •  $lapTimeStr")
            .setContentText("Total: $totalTimeStr  |  $lockStatusStr")
            .setSubText(if (isRunning) "ACTIVE RUN" else "READY")
            .setContentIntent(contentIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .addAction(R.drawable.ic_media_prev, "- Lap", prevPendingIntent)
            .addAction(playPauseIcon, playPauseTitle, playPausePendingIntent)
            .addAction(R.drawable.ic_media_lap, "+ Lap", lapPendingIntent)
            .addAction(lockIcon, lockTitle, toggleLockPendingIntent)
            .setStyle(
                MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        return builder.build()
    }

    private fun updateNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    fun startTimer() {
        if (!isRunning) {
            isRunning = true
            startSilentAudio()
            handler.removeCallbacks(tickerRunnable)
            handler.post(tickerRunnable)
            updatePlaybackState()
            updateNotification()
            dispatchStateToFlutter()
        }
    }

    fun pauseTimer() {
        if (isRunning) {
            isRunning = false
            stopSilentAudio()
            handler.removeCallbacks(tickerRunnable)
            updatePlaybackState()
            updateNotification()
            dispatchStateToFlutter()
        }
    }

    fun toggleTimer() {
        if (isRunning) pauseTimer() else startTimer()
    }

    fun triggerLap() {
        val lapNum = laps.size
        val recordedLapTime = currentLapSeconds
        laps.add(recordedLapTime)
        currentLapSeconds = 0

        updateMetadata()
        updateNotification()
        dispatchLapToFlutter(lapNum, recordedLapTime, totalSeconds)
        dispatchStateToFlutter()
    }

    /**
     * Deletes the last recorded lap, merges its duration back to current lap,
     * and decrements lap count back by 1.
     */
    fun deleteLastLap(): Boolean {
        if (laps.isNotEmpty()) {
            val removedTime = laps.removeAt(laps.size - 1)
            currentLapSeconds += removedTime

            updateMetadata()
            updateNotification()
            dispatchLapDeletedToFlutter(removedTime, laps.size)
            dispatchStateToFlutter()
            return true
        }
        return false
    }

    fun toggleVolumeLock() {
        isVolumeLocked = !isVolumeLocked
        applyVolumeInterceptionMode()
        updatePlaybackState()
        updateMetadata()
        updateNotification()
        dispatchStateToFlutter()
    }

    fun finishRun(): Map<String, Any> {
        pauseTimer()
        stopSilentAudio()
        if (currentLapSeconds > 0) {
            laps.add(currentLapSeconds)
        }
        val summary = mapOf(
            "totalSeconds" to totalSeconds,
            "laps" to ArrayList(laps)
        )
        totalSeconds = 0
        currentLapSeconds = 0
        laps.clear()
        dispatchStateToFlutter()
        return summary
    }

    private fun dispatchTickToFlutter() {
        handler.post {
            methodChannel?.invokeMethod("onTick", mapOf(
                "totalSeconds" to totalSeconds,
                "lapSeconds" to currentLapSeconds
            ))
        }
    }

    private fun dispatchLapToFlutter(lapNumber: Int, lapTime: Int, totalTime: Int) {
        handler.post {
            methodChannel?.invokeMethod("onLapRecorded", mapOf(
                "lapNumber" to lapNumber,
                "lapTime" to lapTime,
                "totalTime" to totalTime
            ))
        }
    }

    private fun dispatchLapDeletedToFlutter(restoredTime: Int, newLapNumber: Int) {
        handler.post {
            methodChannel?.invokeMethod("onLapDeleted", mapOf(
                "restoredTime" to restoredTime,
                "currentLapNumber" to newLapNumber,
                "totalSeconds" to totalSeconds,
                "currentLapSeconds" to currentLapSeconds,
                "laps" to ArrayList(laps)
            ))
        }
    }

    private fun dispatchStateToFlutter() {
        handler.post {
            methodChannel?.invokeMethod("onStateChanged", mapOf(
                "isRunning" to isRunning,
                "isVolumeLocked" to isVolumeLocked,
                "totalSeconds" to totalSeconds,
                "currentLapSeconds" to currentLapSeconds,
                "laps" to ArrayList(laps)
            ))
        }
    }

    private fun createPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, RunTrackerService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Lock Run Tracker Session",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Live Lock Screen notifications and lap tracking"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LockRunTracker:ServiceWakeLock")
            wakeLock?.acquire(12 * 60 * 60 * 1000L) // 12 hours safety ceiling
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null
    }

    private fun startSilentAudio() {
        try {
            if (silentAudioTrack == null) {
                val sampleRate = 8000
                val minBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                val bufferSize = if (minBufferSize > 0) minBufferSize else 1024
                val silentBuffer = ByteArray(bufferSize) // Zeroed bytes = complete silence

                silentAudioTrack = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(bufferSize)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                silentAudioTrack?.write(silentBuffer, 0, bufferSize)
                silentAudioTrack?.setLoopPoints(0, bufferSize / 2, -1)
            }
            if (silentAudioTrack?.playState != AudioTrack.PLAYSTATE_PLAYING) {
                silentAudioTrack?.play()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopSilentAudio() {
        try {
            if (silentAudioTrack?.playState == AudioTrack.PLAYSTATE_PLAYING) {
                silentAudioTrack?.pause()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun releaseSilentAudio() {
        try {
            silentAudioTrack?.stop()
            silentAudioTrack?.release()
            silentAudioTrack = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacks(tickerRunnable)
        releaseWakeLock()
        releaseSilentAudio()
        if (::mediaSession.isInitialized) {
            mediaSession.isActive = false
            mediaSession.release()
        }
        handler.post {
            methodChannel?.invokeMethod("onServiceStopped", null)
        }
        instance = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val CHANNEL_ID = "lock_run_tracker_channel"
        const val NOTIFICATION_ID = 4040

        const val ACTION_PLAY_PAUSE = "com.lockrun.tracker.ACTION_PLAY_PAUSE"
        const val ACTION_LAP = "com.lockrun.tracker.ACTION_LAP"
        const val ACTION_PREV = "com.lockrun.tracker.ACTION_PREV"
        const val ACTION_TOGGLE_LOCK = "com.lockrun.tracker.ACTION_TOGGLE_LOCK"
        const val ACTION_STOP = "com.lockrun.tracker.ACTION_STOP"

        var instance: RunTrackerService? = null
        var methodChannel: MethodChannel? = null

        var isRunning: Boolean = false
            private set
        var isVolumeLocked: Boolean = true
            private set
        var totalSeconds: Int = 0
            private set
        var currentLapSeconds: Int = 0
            private set
        val laps: MutableList<Int> = mutableListOf()

        fun startTimer() {
            instance?.startTimer()
        }

        fun pauseTimer() {
            instance?.pauseTimer()
        }

        fun toggleTimer() {
            instance?.toggleTimer()
        }

        fun triggerLap() {
            instance?.triggerLap()
        }

        fun deleteLastLap(): Boolean {
            return instance?.deleteLastLap() ?: false
        }

        fun toggleVolumeLock() {
            instance?.toggleVolumeLock()
        }

        fun finishRun(): Map<String, Any> {
            return instance?.finishRun() ?: mapOf(
                "totalSeconds" to totalSeconds,
                "laps" to ArrayList(laps)
            )
        }

        private fun formatSeconds(seconds: Int): String {
            val m = (seconds % 3600) / 60
            val s = seconds % 60
            val h = seconds / 3600
            return if (h > 0) {
                String.format("%02d:%02d:%02d", h, m, s)
            } else {
                String.format("%02d:%02d", m, s)
            }
        }
    }
}
