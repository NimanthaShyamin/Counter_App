package com.lockrun.lock_run_tracker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL_NAME = "com.lockrun.tracker/service"
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 9001

        @Volatile
        var isActivityVisible: Boolean = false
    }

    private var methodChannel: MethodChannel? = null
    private var lastVolumeEventTime: Long = 0L
    private val VOLUME_DEBOUNCE_MS = 300L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureLockScreenFlags(true)
    }

    override fun onResume() {
        super.onResume()
        isActivityVisible = true
    }

    override fun onPause() {
        super.onPause()
        isActivityVisible = false
    }

    /**
     * Configures the window to show over the lock screen and turn the screen on.
     * Keeps screen on during workout sessions when enabled.
     */
    private fun configureLockScreenFlags(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        }
        if (enabled) {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        } else {
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun configureKeepScreenOn(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        RunTrackerService.methodChannel = methodChannel

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeService" -> {
                    checkAndRequestNotificationPermission()
                    val serviceIntent = Intent(this, RunTrackerService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(this, serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    configureLockScreenFlags(true)
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    checkAndRequestNotificationPermission()
                    result.success(true)
                }
                "setLockScreenMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    configureLockScreenFlags(enabled)
                    result.success(true)
                }
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    configureKeepScreenOn(enabled)
                    result.success(true)
                }
                "toggleTimer" -> {
                    RunTrackerService.toggleTimer()
                    result.success(null)
                }
                "triggerLap" -> {
                    RunTrackerService.triggerLap()
                    result.success(null)
                }
                "deleteLastLap" -> {
                    val success = RunTrackerService.deleteLastLap()
                    result.success(success)
                }
                "toggleVolumeLock" -> {
                    RunTrackerService.toggleVolumeLock()
                    result.success(null)
                }
                "finishRun" -> {
                    val summary = RunTrackerService.finishRun()
                    stopService(Intent(this, RunTrackerService::class.java))
                    result.success(summary)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun checkAndRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    /**
     * Physical Volume Button Interception
     * Directly intercepts physical volume buttons with zero latency.
     * - KEYCODE_VOLUME_UP   -> Adds exactly 1 Lap (auto-starts timer if idle)
     * - KEYCODE_VOLUME_DOWN -> Removes / Undoes last Lap
     *
     * Repeat count check (event.repeatCount == 0) and debounce window prevent double-counting.
     * Consuming ACTION_DOWN & ACTION_UP suppresses the Android system volume slider HUD.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            if (RunTrackerService.isVolumeLocked) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    val now = System.currentTimeMillis()
                    if (now - lastVolumeEventTime > VOLUME_DEBOUNCE_MS) {
                        lastVolumeEventTime = now
                        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                            // Volume UP -> Add Lap
                            if (!RunTrackerService.isRunning) {
                                RunTrackerService.startTimer()
                            }
                            RunTrackerService.triggerLap()
                        } else {
                            // Volume DOWN -> Remove / Undo Lap
                            RunTrackerService.deleteLastLap()
                        }
                    }
                }
                // Always consume both ACTION_DOWN and ACTION_UP for volume keys when locked
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        super.onDestroy()
        isActivityVisible = false
        RunTrackerService.methodChannel = null
    }
}
