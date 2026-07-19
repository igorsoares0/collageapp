package studio.collage.collageapp

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * Saves exported PNGs to the photo gallery with an EXPLICIT DATE_TAKEN so a
 * burst of carousel panels keeps a deterministic order — gal (used elsewhere)
 * leaves the timestamp to the OS, which stamps every image in the same second
 * and lets the gallery break ties however it likes. Here the Dart side hands a
 * distinct millisecond per panel, so the chronology is exact.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "studio.collage.collageapp/gallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name")
                        val dateTaken = call.argument<Number>("dateTakenMillis")?.toLong()
                        if (bytes == null || name == null) {
                            result.error("bad_args", "bytes and name are required", null)
                            return@setMethodCallHandler
                        }
                        // MediaStore writes touch the disk — keep them off the
                        // UI thread, then hop back to deliver the result (a
                        // MethodChannel result must be invoked on the main thread).
                        Thread {
                            try {
                                saveImage(bytes, name, dateTaken)
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("save_failed", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveImage(bytes: ByteArray, name: String, dateTakenMillis: Long?) {
        val resolver = applicationContext.contentResolver
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val millis = dateTakenMillis ?: System.currentTimeMillis()
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            // DATE_TAKEN is milliseconds; DATE_ADDED/MODIFIED are seconds. Set
            // all three so every gallery sorts by the value we chose.
            put(MediaStore.Images.Media.DATE_TAKEN, millis)
            put(MediaStore.Images.Media.DATE_ADDED, millis / 1000)
            put(MediaStore.Images.Media.DATE_MODIFIED, millis / 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(collection, values)
            ?: throw IOException("MediaStore insert returned null")
        try {
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IOException("openOutputStream returned null")
                out.write(bytes)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
        } catch (e: Exception) {
            // Roll back the half-written (still pending) row so a failed save
            // doesn't leave a broken thumbnail in the gallery.
            resolver.delete(uri, null, null)
            throw e
        }
    }
}
