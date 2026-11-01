package com.swiftmusic.swift_music

import android.content.Context
import com.google.android.gms.wearable.*
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import android.os.Handler
import android.os.Looper

/** Transport is restricted by Data Layer to the same package and signing key. */
class WatchBridge(context: Context, private val channel: MethodChannel) : MessageClient.OnMessageReceivedListener {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    init {
        Wearable.getMessageClient(app).addListener(this)
        channel.setMethodCallHandler { call, result ->
            if (call.method != "publish") { result.notImplemented(); return@setMethodCallHandler }
            val values = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val request = PutDataMapRequest.create("/swift/state")
            request.dataMap.putString("json", JSONObject(values).toString())
            Wearable.getDataClient(app).putDataItem(request.asPutDataRequest())
                .addOnSuccessListener { result.success(null) }
                .addOnFailureListener { result.error("watch_unavailable", "Jam tangan belum terhubung", null) }
        }
    }
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/swift/command" || event.data.size > 1024) return
        val json = try { JSONObject(String(event.data, Charsets.UTF_8)) } catch (_: Exception) { return }
        val args = mutableMapOf<String, Any>("action" to json.optString("action"))
        if (json.has("value")) args["value"] = json.optDouble("value")
        main.post {
            channel.invokeMethod("command", args, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result is Map<*, *>) {
                        val data = PutDataMapRequest.create("/swift/state")
                        data.dataMap.putString("json", JSONObject(result).toString())
                        Wearable.getDataClient(app).putDataItem(data.asPutDataRequest().setUrgent())
                    }
                }
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            })
        }
    }
}
