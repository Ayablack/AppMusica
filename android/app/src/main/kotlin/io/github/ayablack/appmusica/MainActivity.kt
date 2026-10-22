package io.github.ayablack.appmusica

import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Laboratório da Fase 0: confirma se a tela está realmente apagada.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "appmusica/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInteractive" -> {
                        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(power.isInteractive)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
