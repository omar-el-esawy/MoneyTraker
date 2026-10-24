package com.example.money_traker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingBackupPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePublicBackup" -> savePublicBackup(call, result)
                    "scanPublicBackups" -> background(result) {
                        PublicBackupStore.scan(applicationContext)
                    }
                    "stagePublicBackup" -> {
                        val name = call.argument<String>("name")
                        if (name.isNullOrBlank()) {
                            result.error("bad_args", "Missing backup name", null)
                            return@setMethodCallHandler
                        }
                        background(result) {
                            PublicBackupStore.stage(applicationContext, name)
                        }
                    }
                    "requestPublicBackupAccess" -> requestPublicBackupAccess(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun savePublicBackup(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val name = call.argument<String>("name")
        val keepDays = call.argument<Int>("keepDays") ?: defaultKeepDays
        if (path.isNullOrBlank() || name.isNullOrBlank()) {
            result.error("bad_args", "Missing backup file", null)
            return
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

    private fun requestPublicBackupAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success("granted")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
            result.success("granted")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            openAllFilesAccess()
            result.success("settings")
            return
        }
        if (checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
            result.success("granted")
            return
        }
        pendingBackupPermission?.success("denied")
        pendingBackupPermission = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
            backupPermissionRequest,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != backupPermissionRequest) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val pending = pendingBackupPermission
        pendingBackupPermission = null
        pending?.success(if (granted) "granted" else "denied")
    }

    private fun openAllFilesAccess() {
        val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:$packageName")
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { result.error("backup_failed", e.message, null) }
            }
        }.start()
    }

    companion object {
        private const val CHANNEL = "com.example.money_traker/backup"
        private const val defaultKeepDays = 10
        private const val backupPermissionRequest = 4107
    }
}
