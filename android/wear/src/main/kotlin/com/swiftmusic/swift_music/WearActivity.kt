package com.swiftmusic.swift_music

import android.app.Activity
import android.os.Bundle
import android.graphics.Color
import android.view.Gravity
import android.widget.*
import com.google.android.gms.wearable.*
import org.json.JSONObject

/** Native widgets keep the companion small; no Flutter engine on the watch. */
class WearActivity : Activity(), DataClient.OnDataChangedListener {
    private lateinit var title: TextView
    private lateinit var artist: TextView
    private lateinit var status: TextView
    private lateinit var play: Button
    private lateinit var volume: SeekBar
    private var playing = false
    private var updating = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val scroll = ScrollView(this)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(28, 28, 28, 36)
            setBackgroundColor(Color.rgb(18,18,18))
        }
        fun label(size: Float) = TextView(this).apply {
            textSize = size; gravity = Gravity.CENTER; setTextColor(Color.WHITE)
            root.addView(this, LinearLayout.LayoutParams(-1,-2))
        }
        title = label(18f).apply { text = "Swift Music" }
        artist = label(12f)
        status = label(11f).apply { text = "Buka Swift Music di ponsel terpasang" }
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER }
        root.addView(row)
        fun control(text: String, action: () -> String): Button = Button(this).apply {
            this.text = text; minWidth = 0; minimumWidth = 0
            contentDescription = when(text) { "|‹" -> "Lagu sebelumnya"; "›|" -> "Lagu berikutnya"; else -> "Putar atau jeda" }
            row.addView(this, LinearLayout.LayoutParams(0,52,1f))
            setOnClickListener { send(action()) }
        }
        control("|‹") { "previous" }
        play = control("▶") { if (playing) "pause" else "play" }
        control("›|") { "next" }
        volume = SeekBar(this).apply {
            max = 100; contentDescription = "Volume aplikasi"
            root.addView(this, LinearLayout.LayoutParams(-1,48))
            setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar?, value: Int, fromUser: Boolean) {}
                override fun onStartTrackingTouch(bar: SeekBar?) {}
                override fun onStopTrackingTouch(bar: SeekBar?) { if (!updating) send("volume", progress / 100.0) }
            })
        }
        root.addView(Button(this).apply { text = "Hubungkan ulang"; setOnClickListener { send("state") } })
        scroll.addView(root); setContentView(scroll)
    }
    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
        // Cached state may be stale: label it until a fresh response arrives.
        Wearable.getDataClient(this).dataItems.addOnSuccessListener { buffer ->
            try { for (item in buffer) if (item.uri.path == "/swift/state") render(DataMapItem.fromDataItem(item).dataMap.getString("json"), true) }
            finally { buffer.release() }
        }
        send("state")
    }
    override fun onPause() { Wearable.getDataClient(this).removeListener(this); super.onPause() }
    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) if (event.type == DataEvent.TYPE_CHANGED && event.dataItem.uri.path == "/swift/state") {
            render(DataMapItem.fromDataItem(event.dataItem).dataMap.getString("json"), false)
        }
    }
    private fun render(raw: String?, cached: Boolean) {
        val data = try { JSONObject(raw ?: return) } catch (_: Exception) { return }
        runOnUiThread {
            title.text = data.optString("title", "Swift Music"); artist.text = data.optString("artist")
            playing = data.optBoolean("playing"); play.text = if (playing) "Ⅱ" else "▶"
            updating = true; volume.progress = (data.optDouble("volume",1.0)*100).toInt(); updating = false
            val old = System.currentTimeMillis() - data.optLong("updatedAt") > 15000
            status.text = if (cached || old) "Status terakhir • hubungkan ponsel" else if (playing) "Sedang diputar di ponsel" else "Dijeda di ponsel"
        }
    }
    private fun send(action: String, value: Double? = null) {
        val json = JSONObject().put("action", action)
        if (value != null) json.put("value", value)
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            if (nodes.isEmpty()) status.text = "Ponsel belum terhubung"
            for (node in nodes) Wearable.getMessageClient(this).sendMessage(node.id, "/swift/command", json.toString().toByteArray())
                .addOnFailureListener { status.text = "Gagal mengirim • buka aplikasi ponsel" }
        }.addOnFailureListener { status.text = "Koneksi belum tersedia" }
    }
}
