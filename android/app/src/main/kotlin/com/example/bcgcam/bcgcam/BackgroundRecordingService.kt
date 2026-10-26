package com.example.bcgcam.bcgcam

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.io.File

class BackgroundRecordingService : Service() {

    companion object {
        private const val TAG = "BackgroundRecordingSvc"

        const val ACTION_START = "com.example.bcgcam.ACTION_START"
        const val ACTION_STOP = "com.example.bcgcam.ACTION_STOP"
        const val ACTION_CANCEL = "com.example.bcgcam.ACTION_CANCEL"

        const val EXTRA_CAMERA_ID = "extra_camera_id"
        const val EXTRA_CAMERA_NAME = "extra_camera_name"
        const val EXTRA_QUALITY = "extra_quality"
        const val EXTRA_DURATION_SECONDS = "extra_duration_seconds"
        const val EXTRA_AUDIO_ENABLED = "extra_audio_enabled"

        // Active state accessible by MainActivity
        var instance: BackgroundRecordingService? = null
            private set

        var isServiceRunning: Boolean = false
            private set

        var currentState: String = "IDLE" // IDLE, STARTING, RECORDING, STOPPING
            private set

        var activeCameraId: String = "0"
            private set
        var activeCameraName: String = "Rear Camera"
            private set
        var activeQuality: String = "1080p"
            private set
        var audioEnabled: Boolean = true
            private set
        var totalDurationSeconds: Int = 60
            private set
        var elapsedSeconds: Int = 0
            private set
        var remainingSeconds: Int = 60
            private set
        var currentOutputFilePath: String? = null
            private set

        var stateListener: ((Map<String, Any?>) -> Unit)? = null
        var completionListener: ((Map<String, Any?>) -> Unit)? = null

        fun getStatusMap(): Map<String, Any?> {
            return mapOf(
                "isRecording" to (currentState == "RECORDING"),
                "status" to currentState,
                "elapsedSeconds" to elapsedSeconds,
                "remainingSeconds" to remainingSeconds,
                "totalDurationSeconds" to totalDurationSeconds,
                "cameraId" to activeCameraId,
                "cameraName" to activeCameraName,
                "quality" to activeQuality,
                "audioEnabled" to audioEnabled,
                "filePath" to currentOutputFilePath
            )
        }
    }

    private val cameraEngine = CameraRecorderEngine()
    private var wakeLock: PowerManager.WakeLock? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var timerRunnable: Runnable? = null
    private var currentFile: File? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isServiceRunning = true
        NotificationHelper.createNotificationChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY

        when (action) {
            ACTION_START -> {
                val camId = intent.getStringExtra(EXTRA_CAMERA_ID) ?: "0"
                val camName = intent.getStringExtra(EXTRA_CAMERA_NAME) ?: "Rear Camera"
                val quality = intent.getStringExtra(EXTRA_QUALITY) ?: "1080p"
                val duration = intent.getIntExtra(EXTRA_DURATION_SECONDS, 60)
                val audio = intent.getBooleanExtra(EXTRA_AUDIO_ENABLED, true)

                handleStartRecording(camId, camName, quality, duration, audio)
            }
            ACTION_STOP -> {
                handleStopRecording(isUserStop = true)
            }
            ACTION_CANCEL -> {
                handleCancelRecording()
            }
        }

        return START_NOT_STICKY
    }

    private fun handleStartRecording(
        camId: String,
        camName: String,
        quality: String,
        durationSeconds: Int,
        audio: Boolean
    ) {
        if (currentState == "RECORDING" || currentState == "STARTING") {
            Log.w(TAG, "Recording is already active or starting")
            return
        }

        currentState = "STARTING"
        activeCameraId = camId
        activeCameraName = camName
        activeQuality = quality
        totalDurationSeconds = durationSeconds
        elapsedSeconds = 0
        remainingSeconds = durationSeconds
        audioEnabled = audio

        // 1. Prepare wake lock to prevent CPU sleep when display is off
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "BcgCam:BackgroundRecordingWakeLock"
        ).apply {
            setReferenceCounted(false)
            acquire((durationSeconds + 60) * 1000L)
        }

        // 2. Start Foreground Service with camera and optional microphone type
        val initialNotification = NotificationHelper.buildRecordingNotification(
            this,
            0,
            durationSeconds,
            camName,
            quality
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                if (audio && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                ServiceCompat.startForeground(
                    this,
                    NotificationHelper.NOTIFICATION_ID,
                    initialNotification,
                    serviceType
                )
            } else {
                startForeground(NotificationHelper.NOTIFICATION_ID, initialNotification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service: ${e.message}", e)
            cleanupAndStopService("Failed to start foreground service: ${e.message}")
            return
        }

        // 3. Create target output file
        val outputFile = MediaFileManager.createOutputFile(this)
        currentFile = outputFile
        currentOutputFilePath = outputFile.absolutePath

        broadcastState()

        // 4. Start Camera2 Recording Engine
        cameraEngine.startRecording(
            context = this,
            cameraId = camId,
            quality = quality,
            audioEnabled = audio,
            outputFile = outputFile,
            onStarted = {
                mainHandler.post {
                    currentState = "RECORDING"
                    startTimer()
                    broadcastState()
                }
            },
            onError = { errorMsg ->
                mainHandler.post {
                    Log.e(TAG, "Recording engine error: $errorMsg")
                    cleanupAndStopService(errorMsg)
                }
            }
        )
    }

    private fun startTimer() {
        stopTimer()
        timerRunnable = object : Runnable {
            override fun run() {
                if (currentState == "RECORDING") {
                    elapsedSeconds++
                    remainingSeconds--

                    // Update persistent notification
                    updateNotification()
                    broadcastState()

                    if (remainingSeconds <= 0) {
                        Log.i(TAG, "Duration expired! Automatically stopping recording.")
                        handleStopRecording(isUserStop = false)
                    } else {
                        mainHandler.postDelayed(this, 1000)
                    }
                }
            }
        }
        mainHandler.postDelayed(timerRunnable!!, 1000)
    }

    private fun stopTimer() {
        timerRunnable?.let { mainHandler.removeCallbacks(it) }
        timerRunnable = null
    }

    private fun updateNotification() {
        try {
            val notification = NotificationHelper.buildRecordingNotification(
                this,
                elapsedSeconds,
                remainingSeconds,
                activeCameraName,
                activeQuality
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.notify(NotificationHelper.NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update notification: ${e.message}")
        }
    }

    private fun handleStopRecording(isUserStop: Boolean) {
        if (currentState == "STOPPING" || currentState == "IDLE") return
        currentState = "STOPPING"
        stopTimer()
        broadcastState()

        cameraEngine.stopRecording { success ->
            mainHandler.post {
                val file = currentFile
                if (file != null && file.exists() && file.length() > 0) {
                    val durationMs = elapsedSeconds * 1000L
                    MediaFileManager.registerVideoInMediaStore(this@BackgroundRecordingService, file, durationMs)
                    NotificationHelper.showCompletionNotification(
                        this@BackgroundRecordingService,
                        file.name,
                        elapsedSeconds
                    )

                    val completionMap = mapOf(
                        "event" to "finished",
                        "filePath" to file.absolutePath,
                        "fileName" to file.name,
                        "durationSeconds" to elapsedSeconds,
                        "sizeBytes" to file.length(),
                        "reason" to if (isUserStop) "user_stopped" else "duration_completed"
                    )
                    completionListener?.invoke(completionMap)
                } else {
                    Log.w(TAG, "Output file was empty or missing on stop")
                }

                cleanupAndStopService(null)
            }
        }
    }

    private fun handleCancelRecording() {
        currentState = "STOPPING"
        stopTimer()
        broadcastState()

        cameraEngine.stopRecording {
            mainHandler.post {
                currentFile?.let { file ->
                    if (file.exists()) {
                        file.delete()
                        Log.i(TAG, "Cancelled recording, deleted file: ${file.name}")
                    }
                }

                val cancelMap = mapOf(
                    "event" to "cancelled",
                    "reason" to "user_cancelled"
                )
                completionListener?.invoke(cancelMap)

                cleanupAndStopService(null)
            }
        }
    }

    private fun broadcastState() {
        val stateMap = getStatusMap()
        stateListener?.invoke(stateMap)
    }

    private fun cleanupAndStopService(errorMessage: String?) {
        stopTimer()
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing wake lock: ${e.message}")
        }
        wakeLock = null

        currentState = "IDLE"
        currentOutputFilePath = null
        currentFile = null

        if (errorMessage != null) {
            val errorMap = mapOf(
                "event" to "error",
                "error" to errorMessage
            )
            completionListener?.invoke(errorMap)
        }

        broadcastState()

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        isServiceRunning = false
        instance = null
        stopTimer()
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (ignored: Exception) {}
        wakeLock = null
        currentState = "IDLE"
    }
}
