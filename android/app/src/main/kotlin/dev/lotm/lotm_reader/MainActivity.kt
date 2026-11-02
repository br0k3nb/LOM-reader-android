package dev.lotm.lotm_reader

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var exportText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.lotm.reader/storage")
            .setMethodCallHandler { call, result ->
                if (call.method != "usage") { result.notImplemented(); return@setMethodCallHandler }
                Thread {
                    try {
                        val seen = mutableSetOf<String>()
                        val dirs = listOf(filesDir, cacheDir, codeCacheDir,
                            java.io.File(applicationInfo.dataDir, "databases"),
                            java.io.File(applicationInfo.dataDir, "shared_prefs"))
                        var dataBytes = 0L
                        for (dir in dirs) {
                            dir.walkTopDown().forEach { file ->
                                if (file.isFile && seen.add(file.canonicalPath)) dataBytes += file.length()
                            }
                        }
                        val apkPaths = listOf(applicationInfo.sourceDir) + (applicationInfo.splitSourceDirs?.toList() ?: emptyList())
                        val apkBytes = apkPaths.sumOf { java.io.File(it).length() }
                        runOnUiThread { result.success(mapOf("appBytes" to apkBytes, "dataBytes" to dataBytes, "freeBytes" to filesDir.usableSpace)) }
                    } catch (e: Exception) { runOnUiThread { result.error("storage", e.message, null) } }
                }.start()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.lotm.reader/documents")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "Another document picker is open.", null)
                } else when (call.method) {
                    "export" -> {
                        exportText = call.argument<String>("text")
                        pending = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                        }
                        try { startActivityForResult(intent, 701) }
                        catch (e: Exception) { pending = null; exportText = null; result.error("picker", e.message, null) }
                    }
                    "import" -> {
                        pending = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                        }
                        try { startActivityForResult(intent, 702) }
                        catch (e: Exception) { pending = null; result.error("picker", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Used for Android's system document picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 701 && requestCode != 702) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { exportText = null; result.success(null); return }
        val text = exportText
        exportText = null
        Thread {
            try {
                if (requestCode == 701) {
                    contentResolver.openOutputStream(uri, "wt")?.use { it.write((text ?: "").toByteArray(Charsets.UTF_8)) }
                        ?: throw IllegalStateException("Unable to open the selected file.")
                    runOnUiThread { result.success(true) }
                } else {
                    val bytes = contentResolver.openInputStream(uri)?.use { stream ->
                        val buffer = java.io.ByteArrayOutputStream()
                        val chunk = ByteArray(8192)
                        var count = stream.read(chunk)
                        while (count != -1) {
                            buffer.write(chunk, 0, count)
                            if (buffer.size() > 5 * 1024 * 1024) throw IllegalArgumentException("Backup exceeds 5 MB.")
                            count = stream.read(chunk)
                        }
                        buffer.toByteArray()
                    } ?: throw IllegalStateException("Unable to open the selected file.")
                    runOnUiThread { result.success(bytes.toString(Charsets.UTF_8)) }
                }
            } catch (e: Exception) { runOnUiThread { result.error("document", e.message, null) } }
        }.start()
    }
}
