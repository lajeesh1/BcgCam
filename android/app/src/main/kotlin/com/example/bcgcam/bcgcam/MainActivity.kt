package com.example.bcgcam.bcgcam

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.example.bcgcam/recorder"
    private val EVENT_CHANNEL = "com.example.bcgcam/recorder_events"

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Send initial state immediately
                    eventSink?.success(
                        mapOf(
                            "event" to "status",
                            "data" to BackgroundRecordingService.getStatusMap()
                        )
                    )
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        // Connect Service listeners to EventSink
        BackgroundRecordingService.stateListener = { stateMap ->
            runOnUiThread {
                eventSink?.success(
                    mapOf(
                        "event" to "status",
                        "data" to stateMap
                    )
                )
            }
        }

        BackgroundRecordingService.completionListener = { completionMap ->
            runOnUiThread {
                eventSink?.success(completionMap)
            }
        }

        // Setup MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableCameras" -> {
                    try {
                        val cameras = CameraRecorderEngine.getAvailableCameras(this)
                        val list = cameras.map {
                            mapOf(
                                "id" to it.id,
                                "lensFacing" to it.lensFacing,
                                "name" to it.name,
                                "supportedResolutions" to it.supportedResolutions
                            )
                        }
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("CAMERA_ERROR", e.message, null)
                    }
                }

                "startRecording" -> {
                    try {
                        val cameraId = call.argument<String>("cameraId") ?: "0"
                        val cameraName = call.argument<String>("cameraName") ?: "Rear Camera"
                        val quality = call.argument<String>("quality") ?: "1080p"
                        val durationSeconds = call.argument<Int>("durationSeconds") ?: 60
                        val audioEnabled = call.argument<Boolean>("audioEnabled") ?: true

                        val serviceIntent = Intent(this, BackgroundRecordingService::class.java).apply {
                            action = BackgroundRecordingService.ACTION_START
                            putExtra(BackgroundRecordingService.EXTRA_CAMERA_ID, cameraId)
                            putExtra(BackgroundRecordingService.EXTRA_CAMERA_NAME, cameraName)
                            putExtra(BackgroundRecordingService.EXTRA_QUALITY, quality)
                            putExtra(BackgroundRecordingService.EXTRA_DURATION_SECONDS, durationSeconds)
                            putExtra(BackgroundRecordingService.EXTRA_AUDIO_ENABLED, audioEnabled)
                        }

                        ContextCompat.startForegroundService(this, serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message, null)
                    }
                }

                "stopRecording" -> {
                    try {
                        val serviceIntent = Intent(this, BackgroundRecordingService::class.java).apply {
                            action = BackgroundRecordingService.ACTION_STOP
                        }
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_FAILED", e.message, null)
                    }
                }

                "cancelRecording" -> {
                    try {
                        val serviceIntent = Intent(this, BackgroundRecordingService::class.java).apply {
                            action = BackgroundRecordingService.ACTION_CANCEL
                        }
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_FAILED", e.message, null)
                    }
                }

                "getRecordingStatus" -> {
                    result.success(BackgroundRecordingService.getStatusMap())
                }

                "getStorageInfo" -> {
                    try {
                        val info = MediaFileManager.getStorageInfo(this)
                        result.success(info)
                    } catch (e: Exception) {
                        result.error("STORAGE_ERROR", e.message, null)
                    }
                }

                "getSavedRecordings" -> {
                    try {
                        val recordings = MediaFileManager.getSavedRecordings(this)
                        result.success(recordings)
                    } catch (e: Exception) {
                        result.error("GALLERY_ERROR", e.message, null)
                    }
                }

                "deleteRecording" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARG", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    val deleted = MediaFileManager.deleteRecording(this, filePath)
                    result.success(deleted)
                }

                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }

                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback to general settings
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("SETTINGS_ERROR", ex.message, null)
                        }
                    }
                }

                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
