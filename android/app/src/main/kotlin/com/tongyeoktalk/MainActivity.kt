package com.tongyeoktalk

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.ads.AdRequest

class MainActivity : FlutterActivity() {
    private var contacts: ContactsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        contacts?.close()
        contacts = ContactsBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tongyeok/ad_test_device")
            .setMethodCallHandler { call, result ->
                if (call.method == "isTestDevice") {
                    result.success(AdRequest.Builder().build().isTestDevice(this))
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        if (contacts?.permissionResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (contacts?.pickerResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        contacts?.close()
        contacts = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("tongyeok_messages", "통역톡", NotificationManager.IMPORTANCE_HIGH)
            channel.enableVibration(true)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
