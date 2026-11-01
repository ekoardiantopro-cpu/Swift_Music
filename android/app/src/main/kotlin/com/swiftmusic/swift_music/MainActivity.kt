package com.swiftmusic.swift_music

import com.ryanheise.audioservice.AudioServiceActivity
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.media.MediaMetadataRetriever
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.os.Build
import android.view.WindowManager
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pendingFolder: MethodChannel.Result? = null
    private var folder: Uri? = null
    private val allowed = mutableSetOf<String>()
    private val streams = mutableMapOf<Int, InputStream>()
    private var nextHandle = 0
    private var watchBridge: WatchBridge? = null
    private val spotifyConnectChannel = "com.swiftmusic/spotify_connect"

    private external fun nativeSpotifyStatus(): String

    companion object {
        init {
            try {
                System.loadLibrary("swift_spotify_connect")
            } catch (_: UnsatisfiedLinkError) {
                // Flutter receives a clear "native module unavailable" response below.
            }
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, spotifyConnectChannel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            val intent = Intent(this, SpotifyConnectService::class.java)
                                .setAction(SpotifyConnectService.ACTION_START)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
                            else startService(intent)
                            result.success(true)
                        }
                        "stop" -> {
                            stopService(Intent(this, SpotifyConnectService::class.java))
                            result.success(null)
                        }
                        "status" -> result.success(nativeSpotifyStatus())
                        else -> result.notImplemented()
                    }
                } catch (error: UnsatisfiedLinkError) {
                    result.error("native_unavailable", "Spotify Connect native belum terpasang.", null)
                } catch (error: Exception) {
                    result.error("spotify_connect", error.message, null)
                }
            }
        watchBridge = WatchBridge(applicationContext, MethodChannel(engine.dartExecutor.binaryMessenger, "com.swiftmusic/watch"))
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.swiftmusic/system").setMethodCallHandler { call, result ->
            if (call.method == "keepAwake") {
                if (call.argument<Boolean>("enabled") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(null)
            } else result.notImplemented()
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.swiftmusic/metadata")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") { result.notImplemented(); return@setMethodCallHandler }
                worker.execute {
                    try {
                        val tags = readMetadata(call)
                        runOnUiThread { result.success(tags) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("metadata", error.message, null) }
                    }
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.swiftmusic/music_folders")
            .setMethodCallHandler { call, result ->
                if (call.method == "pickFolder") {
                    if (pendingFolder != null) {
                        result.error("picker_busy", "Pemilih folder sedang dibuka.", null)
                    } else {
                        pendingFolder = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }, 47021)
                        } catch (error: Exception) {
                            pendingFolder = null
                            result.error("folder_picker", error.message, null)
                        }
                    }
                } else if (call.method in setOf("listFolder", "openFile", "readChunk", "closeFile", "releaseFolder", "restoreFolder", "forgetFolder")) {
                    worker.execute {
                        try {
                            val value = handleFolderCall(call)
                            runOnUiThread { result.success(value) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("folder_io", error.message, null) }
                        }
                    }
                } else result.notImplemented()
            }
    }

    private fun readMetadata(call: MethodCall): Map<String, Any> {
        val root = File(filesDir, "local_music").canonicalFile
        val audio = File(call.argument<String>("path") ?: "").canonicalFile
        val cover = File(call.argument<String>("coverPath") ?: "").canonicalFile
        require(audio.parentFile == root && cover.parentFile == root) { "Path metadata di luar koleksi aplikasi." }
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(audio.path)
            val tags = mutableMapOf<String, Any>()
            for ((name, key) in mapOf("title" to MediaMetadataRetriever.METADATA_KEY_TITLE,
                "artist" to MediaMetadataRetriever.METADATA_KEY_ARTIST,
                "album" to MediaMetadataRetriever.METADATA_KEY_ALBUM,
                "genre" to MediaMetadataRetriever.METADATA_KEY_GENRE,
                "composer" to MediaMetadataRetriever.METADATA_KEY_COMPOSER,
                "writer" to MediaMetadataRetriever.METADATA_KEY_WRITER,
                "year" to MediaMetadataRetriever.METADATA_KEY_YEAR,
                "disc" to MediaMetadataRetriever.METADATA_KEY_DISC_NUMBER,
                "track" to MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER,
                "bitrate" to MediaMetadataRetriever.METADATA_KEY_BITRATE,
                "sampleRate" to MediaMetadataRetriever.METADATA_KEY_SAMPLERATE,
                "bitsPerSample" to MediaMetadataRetriever.METADATA_KEY_BITS_PER_SAMPLE,
                "mimeType" to MediaMetadataRetriever.METADATA_KEY_MIMETYPE)) {
                if (Build.VERSION.SDK_INT < 31 && name in setOf("sampleRate", "bitsPerSample")) continue
                retriever.extractMetadata(key)?.takeIf { it.isNotBlank() }?.let { tags[name] = it }
            }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { tags["durationMs"] = it }
            val image = retriever.embeddedPicture
            if (image != null && image.size <= 8 * 1024 * 1024) {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(image, 0, image.size, bounds)
                var sample = 1
                while (bounds.outWidth / sample > 768 || bounds.outHeight / sample > 768) sample *= 2
                val options = BitmapFactory.Options().apply { inSampleSize = sample }
                BitmapFactory.decodeByteArray(image, 0, image.size, options)?.let { bitmap ->
                    try { cover.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it) } }
                    finally { bitmap.recycle() }
                }
            }
            return tags
        } finally { retriever.release() }
    }

    @Deprecated("Used for the system document tree picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 47021) return
        val reply = pendingFolder ?: return
        pendingFolder = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { reply.success(null); return }
        folder = uri
        try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        catch (_: SecurityException) { /* Temporary access still permits this import. */ }
        val id = DocumentsContract.getTreeDocumentId(uri)
        reply.success(mapOf("uri" to uri.toString(), "name" to id.substringAfter(':').substringAfterLast('/').ifEmpty { "Musik" }))
    }

    private fun handleFolderCall(call: MethodCall): Any? = when (call.method) {
        "restoreFolder" -> {
            val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("URI kosong."))
            require(contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }) { "Izin folder telah berakhir. Pilih ulang folder." }
            folder = uri
            val id = DocumentsContract.getTreeDocumentId(uri)
            mapOf("uri" to uri.toString(), "name" to id.substringAfter(':').substringAfterLast('/').ifEmpty { "Musik" })
        }
        "forgetFolder" -> {
            val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("URI kosong."))
            if (contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }) {
                contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            null
        }
        "listFolder" -> {
            val root = folder ?: throw IllegalStateException("Pilih folder terlebih dahulu.")
            val extensions = (call.argument<List<String>>("extensions") ?: emptyList()).toSet()
            val files = mutableListOf<Map<String, Any>>()
            val directories = java.util.ArrayDeque<String>()
            val visited = mutableSetOf<String>()
            directories.add(DocumentsContract.getTreeDocumentId(root))
            allowed.clear()
            while (!directories.isEmpty()) {
                val id = directories.removeFirst()
                if (!visited.add(id)) continue
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(root, id)
                contentResolver.query(children, arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                ), null, null, null).use { cursor ->
                    if (cursor == null) throw java.io.IOException("Folder tidak dapat dibaca.")
                    while (cursor.moveToNext()) {
                        val childId = cursor.getString(0)
                        val name = cursor.getString(1) ?: continue
                        if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                            directories.add(childId)
                        } else if (name.substringAfterLast('.', "").lowercase(Locale.ROOT) in extensions) {
                            val uri = DocumentsContract.buildDocumentUriUsingTree(root, childId).toString()
                            allowed.add(uri)
                            files.add(mapOf("uri" to uri, "name" to name,
                                "size" to if (cursor.isNull(3)) -1L else cursor.getLong(3),
                                "modifiedMs" to if (cursor.isNull(4)) 0L else cursor.getLong(4)))
                        }
                    }
                }
            }
            files
        }
        "openFile" -> {
            val uri = call.argument<String>("uri") ?: throw IllegalArgumentException("URI kosong.")
            require(uri in allowed) { "File tidak berasal dari folder pilihan." }
            val stream = contentResolver.openInputStream(Uri.parse(uri)) ?: throw java.io.IOException("File tidak dapat dibuka.")
            val handle = ++nextHandle
            streams[handle] = stream
            handle
        }
        "readChunk" -> {
            val stream = streams[call.argument<Int>("handle")] ?: throw java.io.IOException("File sudah ditutup.")
            val buffer = ByteArray(65536)
            val length = stream.read(buffer)
            if (length <= 0) null else if (length == buffer.size) buffer else buffer.copyOf(length)
        }
        "closeFile" -> { streams.remove(call.argument<Int>("handle"))?.close(); null }
        "releaseFolder" -> {
            streams.values.forEach { try { it.close() } catch (_: Exception) {} }
            streams.clear(); allowed.clear(); folder = null; null
        }
        else -> null
    }

    override fun onDestroy() {
        worker.execute {
            streams.values.forEach { try { it.close() } catch (_: Exception) {} }
            streams.clear()
        }
        worker.shutdown()
        super.onDestroy()
    }
    // Flutter menangani route/tab terlebih dahulu. Hanya Back di root yang
    // mencapai callback ini; pertahankan activity dan engine audio di background.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }
}
