package com.contextdrive.app

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val voiceChannel = "contextdrive/voice_alerts"
    private var textToSpeech: TextToSpeech? = null
    private var voiceReady = false
    private var pendingMessage: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        textToSpeech = TextToSpeech(this, this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val message = call.argument<String>("message")
                        if (message.isNullOrBlank()) {
                            result.error("invalid_message", "A voice-alert message is required.", null)
                        } else {
                            speak(message)
                            result.success(null)
                        }
                    }
                    "stop" -> {
                        textToSpeech?.stop()
                        pendingMessage = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onInit(status: Int) {
        voiceReady = status == TextToSpeech.SUCCESS
        if (!voiceReady) return

        textToSpeech?.language = Locale.US
        pendingMessage?.let {
            pendingMessage = null
            speak(it)
        }
    }

    private fun speak(message: String) {
        val tts = textToSpeech ?: return
        if (!voiceReady) {
            pendingMessage = message
            return
        }
        tts.stop()
        tts.speak(message, TextToSpeech.QUEUE_FLUSH, null, "contextdrive-risk-alert")
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }
}
