package com.example.sign_language_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "synapse/llm"
    private lateinit var ttsService: SynapseTtsService

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ttsService = SynapseTtsService(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text").orEmpty()
                        ttsService.speak(text)
                        result.success(null)
                    }
                    "stopSpeaking" -> {
                        ttsService.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (::ttsService.isInitialized) {
            ttsService.shutdown()
        }
        super.onDestroy()
    }
}
