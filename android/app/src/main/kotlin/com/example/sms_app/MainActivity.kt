package com.example.sms_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.os.Environment
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "storage_channel"

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDownloadsPath" -> {
                    val downloadsDir: File = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    result.success(downloadsDir.absolutePath)
                }
                "getExternalStorageRoots" -> {
                    val externalDirs = getExternalFilesDirs(null)
                    val roots = mutableListOf<String>()
                    for (dir in externalDirs) {
                        if (dir != null) {
                            val path = dir.absolutePath
                            val index = path.indexOf("/Android/data")
                            if (index != -1) {
                                val root = path.substring(0, index)
                                roots.add(root)
                            }
                        }
                    }
                    result.success(roots)
                }
                else -> result.notImplemented()
            }
        }
    }
}