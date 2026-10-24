package com.example.money_traker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "savePublicBackup") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val name = call.argument<String>("name")
                val keepDays = call.argument<Int>("keepDays") ?: defaultKeepDays
                if (path.isNullOrBlank() || name.isNullOrBlank()) {
                    result.error("bad_args", "Missing backup file", null)
                    return@setMethodCallHandler
                }
                val appContext = applicationContext
                Thread {
                    try {
                        val saved = PublicBackupStore.save(appContext, path, name, keepDays)
                        runOnUiThread { result.success(saved) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("backup_failed", e.message, null) }
                    }
                }.start()
            }
    }

    companion object {
        private const val CHANNEL = "com.example.money_traker/backup"
        private const val defaultKeepDays = 10
    }
}
