package com.synapse.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * MainActivity for SYNAPSE.
 *
 * Extends FlutterActivity (the standard entry point for Flutter on Android).
 * Plugin registration is handled automatically by Flutter's plugin registrant.
 * The LlamaPlugin is registered here to bridge Dart ↔ native llama.cpp inference.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register auto-generated Flutter plugins (camera, tflite, etc.)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Register the custom LlamaPlugin for local LLM inference via JNI
        LlamaPlugin(flutterEngine.dartExecutor.binaryMessenger)
    }
}
