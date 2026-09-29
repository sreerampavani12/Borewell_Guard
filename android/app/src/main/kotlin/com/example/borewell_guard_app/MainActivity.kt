package com.example.borewell_guard_app

import android.media.MediaPlayer
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var mediaPlayer: MediaPlayer? = null

    private val CHANNEL = "borewell_guard/audio"

    override fun configureFlutterEngine(
        flutterEngine: io.flutter.embedding.engine.FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "playEmergencySound" -> {
                    playEmergencySound()
                    result.success(null)
                }

                "stopEmergencySound" -> {
                    stopEmergencySound()
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun playEmergencySound() {
    try {
        mediaPlayer?.release()
        mediaPlayer = null

        mediaPlayer = MediaPlayer.create(this, R.raw.emergency)

        if (mediaPlayer == null) {
            println("❌ MediaPlayer.create() returned null")
            return
        }

        mediaPlayer?.setOnCompletionListener {
            it.release()
            mediaPlayer = null
        }

        mediaPlayer?.start()

        println("🚨 Emergency MP3 started successfully")

    } catch (e: Exception) {
        println("❌ Emergency sound error: ${e.message}")
        e.printStackTrace()
    }
}
    private fun stopEmergencySound() {

        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        stopEmergencySound()
        super.onDestroy()
    }
}