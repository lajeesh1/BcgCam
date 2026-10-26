package com.example.bcgcam.bcgcam

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Surface
import java.io.File

class CameraRecorderEngine {

    companion object {
        private const val TAG = "CameraRecorderEngine"

        data class CameraInfoData(
            val id: String,
            val lensFacing: String,
            val name: String,
            val supportedResolutions: List<String>
        )

        fun getAvailableCameras(context: Context): List<CameraInfoData> {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val list = mutableListOf<CameraInfoData>()

            try {
                for (id in cameraManager.cameraIdList) {
                    val chars = cameraManager.getCameraCharacteristics(id)
                    val facing = chars.get(CameraCharacteristics.LENS_FACING)

                    val facingStr = when (facing) {
                        CameraCharacteristics.LENS_FACING_FRONT -> "front"
                        CameraCharacteristics.LENS_FACING_BACK -> "back"
                        else -> "external"
                    }
                    val name = when (facing) {
                        CameraCharacteristics.LENS_FACING_FRONT -> "Front Camera"
                        CameraCharacteristics.LENS_FACING_BACK -> "Rear Camera"
                        else -> "Camera $id"
                    }

                    val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    val sizes = map?.getOutputSizes(MediaRecorder::class.java) ?: emptyArray()

                    val supportedQualities = mutableListOf<String>()
                    if (sizes.any { it.width >= 1920 && it.height >= 1080 || it.width >= 1080 && it.height >= 1920 }) {
                        supportedQualities.add("1080p")
                    }
                    if (sizes.any { it.width >= 1280 && it.height >= 720 || it.width >= 720 && it.height >= 1280 }) {
                        supportedQualities.add("720p")
                    }
                    if (sizes.any { it.width >= 640 && it.height >= 480 || it.width >= 480 && it.height >= 640 }) {
                        supportedQualities.add("480p")
                    }
                    if (supportedQualities.isEmpty() && sizes.isNotEmpty()) {
                        supportedQualities.add("480p")
                    }

                    list.add(
                        CameraInfoData(
                            id = id,
                            lensFacing = facingStr,
                            name = name,
                            supportedResolutions = supportedQualities
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error querying cameras: ${e.message}", e)
            }

            // Keep only the primary camera for each facing (one Rear Camera, one Front Camera)
            val uniqueList = mutableListOf<CameraInfoData>()
            val seenFacings = mutableSetOf<String>()
            for (cam in list) {
                if (seenFacings.add(cam.lensFacing)) {
                    uniqueList.add(cam)
                }
            }
            return uniqueList
        }
    }

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var mediaRecorder: MediaRecorder? = null
    private var dummySurfaceTexture: SurfaceTexture? = null
    private var dummySurface: Surface? = null

    var isRecording: Boolean = false
        private set

    private fun startBackgroundThread() {
        if (backgroundThread == null) {
            backgroundThread = HandlerThread("CameraBackgroundThread").apply { start() }
            backgroundHandler = Handler(backgroundThread!!.looper)
        }
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join(1000)
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error stopping background thread", e)
        }
        backgroundThread = null
        backgroundHandler = null
    }

    private fun chooseVideoSize(sizes: Array<Size>, quality: String): Size {
        // Standard landscape aspect ratios for MediaRecorder
        val targetWidth = when (quality.lowercase()) {
            "1080p" -> 1920
            "720p" -> 1280
            "480p" -> 720
            else -> 1280
        }
        val targetHeight = when (quality.lowercase()) {
            "1080p" -> 1080
            "720p" -> 720
            "480p" -> 480
            else -> 720
        }

        // Exact match
        val exact = sizes.firstOrNull {
            (it.width == targetWidth && it.height == targetHeight) ||
            (it.width == targetHeight && it.height == targetWidth)
        }
        if (exact != null) {
            return if (exact.width >= exact.height) exact else Size(exact.height, exact.width)
        }

        // Closest match
        val sorted = sizes.filter { it.width >= it.height }.sortedByDescending { it.width * it.height }
        return when (quality.lowercase()) {
            "1080p" -> sorted.firstOrNull { it.width <= 1920 && it.height <= 1080 } ?: sorted.first()
            "720p" -> sorted.firstOrNull { it.width <= 1280 && it.height <= 720 } ?: sorted.last()
            "480p" -> sorted.firstOrNull { it.width <= 720 && it.height <= 480 } ?: sorted.last()
            else -> sorted.firstOrNull() ?: Size(1280, 720)
        }
    }

    @SuppressLint("MissingPermission")
    fun startRecording(
        context: Context,
        cameraId: String,
        quality: String,
        audioEnabled: Boolean,
        outputFile: File,
        onStarted: () -> Unit,
        onError: (String) -> Unit
    ) {
        startBackgroundThread()

        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        try {
            val chars = cameraManager.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val sizes = map?.getOutputSizes(MediaRecorder::class.java) ?: emptyArray()
            if (sizes.isEmpty()) {
                onError("No supported video sizes for camera $cameraId")
                return
            }

            val videoSize = chooseVideoSize(sizes, quality)
            Log.d(TAG, "Selected video size: ${videoSize.width}x${videoSize.height} for $quality")

            val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
            val lensFacing = chars.get(CameraCharacteristics.LENS_FACING)

            // Calculate bitrate
            val bitRate = when (quality.lowercase()) {
                "1080p" -> 8_000_000
                "720p" -> 4_000_000
                "480p" -> 2_000_000
                else -> 4_000_000
            }

            // Setup MediaRecorder
            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }.apply {
                if (audioEnabled) {
                    setAudioSource(MediaRecorder.AudioSource.CAMCORDER)
                }
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                if (audioEnabled) {
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(128_000)
                    setAudioSamplingRate(44_100)
                }
                setVideoSize(videoSize.width, videoSize.height)
                setVideoFrameRate(30)
                setVideoEncodingBitRate(bitRate)
                setOrientationHint(sensorOrientation)
                setOutputFile(outputFile.absolutePath)
                prepare()
            }

            // Open Camera
            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    try {
                        val recorderSurface = mediaRecorder!!.surface

                        dummySurfaceTexture = SurfaceTexture(10).apply {
                            setDefaultBufferSize(videoSize.width, videoSize.height)
                        }
                        dummySurface = Surface(dummySurfaceTexture)

                        val surfaces = listOf(recorderSurface, dummySurface!!)

                        camera.createCaptureSession(
                            surfaces,
                            object : CameraCaptureSession.StateCallback() {
                                override fun onConfigured(session: CameraCaptureSession) {
                                    if (cameraDevice == null) return
                                    captureSession = session
                                    try {
                                        val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                                            addTarget(recorderSurface)
                                            dummySurface?.let { addTarget(it) }
                                            set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                                            set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                                            set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
                                            set(CaptureRequest.CONTROL_AWB_MODE, CameraMetadata.CONTROL_AWB_MODE_AUTO)
                                        }

                                        session.setRepeatingRequest(builder.build(), null, backgroundHandler)
                                        mediaRecorder?.start()
                                        isRecording = true
                                        Log.i(TAG, "MediaRecorder started successfully!")
                                        onStarted()
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Error starting repeating request or recorder: ${e.message}", e)
                                        cleanup()
                                        onError("Failed to start recording: ${e.message}")
                                    }
                                }

                                override fun onConfigureFailed(session: CameraCaptureSession) {
                                    Log.e(TAG, "CameraCaptureSession configuration failed")
                                    cleanup()
                                    onError("Failed to configure camera capture session")
                                }
                            },
                            backgroundHandler
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "Error setting up capture session: ${e.message}", e)
                        cleanup()
                        onError("Failed to create capture session: ${e.message}")
                    }
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Camera disconnected")
                    camera.close()
                    cameraDevice = null
                    isRecording = false
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    val errorMsg = "Camera device error: $error"
                    Log.e(TAG, errorMsg)
                    camera.close()
                    cameraDevice = null
                    cleanup()
                    onError(errorMsg)
                }
            }, backgroundHandler)

        } catch (e: Exception) {
            Log.e(TAG, "Exception starting camera recording: ${e.message}", e)
            cleanup()
            onError("Camera initialization error: ${e.message}")
        }
    }

    fun stopRecording(onComplete: (Boolean) -> Unit) {
        if (!isRecording && mediaRecorder == null && cameraDevice == null) {
            onComplete(false)
            return
        }

        isRecording = false
        backgroundHandler?.post {
            var success = false
            try {
                captureSession?.stopRepeating()
                captureSession?.abortCaptures()
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping repeating request: ${e.message}")
            }

            try {
                mediaRecorder?.stop()
                success = true
                Log.i(TAG, "MediaRecorder stopped cleanly")
            } catch (e: RuntimeException) {
                // If stopped too soon before frames were written
                Log.w(TAG, "RuntimeException on mediaRecorder.stop(): ${e.message}")
                success = false
            } catch (e: Exception) {
                Log.e(TAG, "Exception on mediaRecorder.stop(): ${e.message}")
                success = false
            }

            cleanup()
            onComplete(success)
        }
    }

    private fun cleanup() {
        try {
            captureSession?.close()
        } catch (ignored: Exception) {}
        captureSession = null

        try {
            cameraDevice?.close()
        } catch (ignored: Exception) {}
        cameraDevice = null

        try {
            mediaRecorder?.reset()
            mediaRecorder?.release()
        } catch (ignored: Exception) {}
        mediaRecorder = null

        try {
            dummySurface?.release()
        } catch (ignored: Exception) {}
        dummySurface = null

        try {
            dummySurfaceTexture?.release()
        } catch (ignored: Exception) {}
        dummySurfaceTexture = null

        isRecording = false
        stopBackgroundThread()
    }
}
