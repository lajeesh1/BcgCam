package com.example.bcgcam.bcgcam

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object MediaFileManager {
    private const val TAG = "MediaFileManager"
    private const val FOLDER_NAME = "BcgCam"

    /**
     * Get the directory where videos are saved.
     * Uses app-specific external Movies dir for direct, unrestricted POSIX writing.
     */
    fun getVideoStorageDirectory(context: Context): File {
        val targetDir = File(context.getExternalFilesDir(Environment.DIRECTORY_MOVIES), FOLDER_NAME)
        if (!targetDir.exists()) {
            targetDir.mkdirs()
        }
        return targetDir
    }

    /**
     * Creates a new output file with timestamped name.
     */
    fun createOutputFile(context: Context): File {
        val dir = getVideoStorageDirectory(context)
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val fileName = "VID_${timestamp}.mp4"
        return File(dir, fileName)
    }

    /**
     * Registers a completed video file into Android's MediaStore so it appears in standard Gallery/Photos apps,
     * and copies to public Movies/BcgCam folder via MediaStore.
     */
    fun registerVideoInMediaStore(context: Context, videoFile: File, durationMs: Long) {
        try {
            MediaScannerConnection.scanFile(
                context,
                arrayOf(videoFile.absolutePath),
                arrayOf("video/mp4")
            ) { path, uri ->
                Log.d(TAG, "MediaScanner scanned $path -> $uri")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, videoFile.name)
                    put(MediaStore.Video.Media.TITLE, videoFile.nameWithoutExtension)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/$FOLDER_NAME")
                    put(MediaStore.Video.Media.DATE_ADDED, System.currentTimeMillis() / 1000)
                    put(MediaStore.Video.Media.DATE_MODIFIED, videoFile.lastModified() / 1000)
                    put(MediaStore.Video.Media.SIZE, videoFile.length())
                    if (durationMs > 0) {
                        put(MediaStore.Video.Media.DURATION, durationMs)
                    }
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }

                val uri = context.contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                if (uri != null) {
                    try {
                        context.contentResolver.openOutputStream(uri)?.use { outStream ->
                            videoFile.inputStream().use { inStream ->
                                inStream.copyTo(outStream)
                            }
                        }
                        values.clear()
                        values.put(MediaStore.Video.Media.IS_PENDING, 0)
                        context.contentResolver.update(uri, values, null, null)
                        Log.i(TAG, "Video successfully published to public Movies/$FOLDER_NAME: $uri")
                    } catch (e: Exception) {
                        Log.w(TAG, "Could not copy stream to public MediaStore: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error registering video in MediaStore: ${e.message}", e)
        }
    }

    /**
     * Generates a cached JPEG thumbnail for a video file.
     */
    fun getOrCreateThumbnail(context: Context, videoFile: File): String? {
        val thumbDir = File(context.cacheDir, "thumbnails")
        if (!thumbDir.exists()) thumbDir.mkdirs()

        val thumbFile = File(thumbDir, "thumb_${videoFile.nameWithoutExtension}.jpg")
        if (thumbFile.exists() && thumbFile.length() > 0) {
            return thumbFile.absolutePath
        }

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoFile.absolutePath)
            val bitmap = retriever.getFrameAtTime(1_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: retriever.getFrameAtTime(0)

            if (bitmap != null) {
                FileOutputStream(thumbFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }
                thumbFile.absolutePath
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate thumbnail for ${videoFile.name}: ${e.message}")
            null
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    /**
     * Lists all saved video recordings in the storage directory.
     */
    fun getSavedRecordings(context: Context): List<Map<String, Any?>> {
        val list = mutableListOf<Map<String, Any?>>()
        val primaryDir = getVideoStorageDirectory(context)
        val legacyDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), FOLDER_NAME)
        val oldFolderDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "BackgroundVideoRecorder")

        val filesToScan = mutableSetOf<File>()
        listOf(primaryDir, legacyDir, oldFolderDir).forEach { dir ->
            if (dir.exists()) {
                dir.listFiles { file -> file.isFile && file.name.endsWith(".mp4", ignoreCase = true) }
                    ?.let { filesToScan.addAll(it) }
            }
        }

        val sortedFiles = filesToScan.sortedByDescending { it.lastModified() }

        for (file in sortedFiles) {
            if (file.length() <= 0) continue

            val retriever = MediaMetadataRetriever()
            var durationMs: Long = 0
            var width = 0
            var height = 0
            try {
                retriever.setDataSource(file.absolutePath)
                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                durationMs = durationStr?.toLongOrNull() ?: 0L
                val widthStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                val heightStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                width = widthStr?.toIntOrNull() ?: 0
                height = heightStr?.toIntOrNull() ?: 0
            } catch (e: Exception) {
                Log.w(TAG, "Could not extract metadata for ${file.name}: ${e.message}")
            } finally {
                try { retriever.release() } catch (ignored: Exception) {}
            }

            val thumbPath = getOrCreateThumbnail(context, file)

            val item = mapOf(
                "id" to file.name,
                "name" to file.name,
                "path" to file.absolutePath,
                "sizeBytes" to file.length(),
                "durationMs" to durationMs,
                "timestamp" to file.lastModified(),
                "width" to width,
                "height" to height,
                "thumbnailPath" to thumbPath
            )
            list.add(item)
        }

        return list
    }

    /**
     * Deletes a recording and its cached thumbnail.
     */
    fun deleteRecording(context: Context, filePath: String): Boolean {
        return try {
            val file = File(filePath)
            var deleted = false
            if (file.exists()) {
                deleted = file.delete()
            }

            // Remove thumbnail
            val thumbDir = File(context.cacheDir, "thumbnails")
            val thumbFile = File(thumbDir, "thumb_${file.nameWithoutExtension}.jpg")
            if (thumbFile.exists()) {
                thumbFile.delete()
            }

            // Remove from MediaStore if registered
            try {
                val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                val selection = "${MediaStore.Video.Media.DATA} = ?"
                context.contentResolver.delete(uri, selection, arrayOf(filePath))
            } catch (ignored: Exception) {}

            deleted
        } catch (e: Exception) {
            Log.e(TAG, "Error deleting file $filePath: ${e.message}")
            false
        }
    }

    /**
     * Returns storage information for the storage volume.
     */
    fun getStorageInfo(context: Context): Map<String, Any> {
        val dir = getVideoStorageDirectory(context)
        val displayPath = "Movies/BcgCam"
        return try {
            val stat = StatFs(dir.path)
            val blockSize = stat.blockSizeLong
            val availableBlocks = stat.availableBlocksLong
            val totalBlocks = stat.blockCountLong
            val freeBytes = availableBlocks * blockSize
            val totalBytes = totalBlocks * blockSize

            mapOf(
                "path" to displayPath,
                "fullPath" to dir.absolutePath,
                "freeBytes" to freeBytes,
                "totalBytes" to totalBytes
            )
        } catch (e: Exception) {
            mapOf(
                "path" to displayPath,
                "fullPath" to dir.absolutePath,
                "freeBytes" to 0L,
                "totalBytes" to 0L
            )
        }
    }
}
