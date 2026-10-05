// native-api-bindgen native UI layer. Apache License, Version 2.0.
package dev.nativeapibindgen.native_api_ui

import android.content.Context
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

/** Registers the `dev.nativeapibindgen/view` platform view type. */
class NativeApiUiPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.platformViewRegistry.registerViewFactory(VIEW_TYPE, NabViewFactory())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    companion object {
        const val VIEW_TYPE = "dev.nativeapibindgen/view"
    }
}

/**
 * Views created by Dart through generated bindings, waiting for their
 * platform view. Called from Dart over JNI.
 */
object NabViewRegistry {
    private val views = ConcurrentHashMap<Long, View>()
    private val next = AtomicLong(1)

    @JvmStatic
    fun register(view: View): Long {
        val id = next.getAndIncrement()
        views[id] = view
        return id
    }

    @JvmStatic
    fun unregister(id: Long) {
        views.remove(id)
    }

    @JvmStatic
    fun get(id: Long): View? = views[id]
}

private class NabViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val id = ((args as? Map<*, *>)?.get("id") as? Number)?.toLong() ?: 0L
        val view = NabViewRegistry.get(id) ?: View(context)
        (view.parent as? ViewGroup)?.removeView(view)
        return object : PlatformView {
            override fun getView(): View = view

            override fun dispose() {}
        }
    }
}
