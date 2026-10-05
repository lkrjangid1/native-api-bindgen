package dev.nativeapibindgen.examples.android_slice

import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val benchBundle = Bundle()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Hand-written MethodChannel equivalents of generated calls, used only
        // by integration_test/bench_test.dart for comparison.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nab/bench")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "noop" -> result.success(null)
                    "bundleSize" -> result.success(benchBundle.size())
                    "parseUri" -> result.success(Uri.parse(call.arguments as String).toString())
                    "copyBytes" -> result.success((call.arguments as ByteArray).copyOf())
                    else -> result.notImplemented()
                }
            }
    }
}
