package com.example.eyecare

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.eyecare.app/screen_time"
    private val notificationPermissionRequestCode = 2001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // فقط اگر کاربر قبلاً خودش مانیتورینگ را خاموش نکرده باشد، موقع
        // باز شدن اپ سرویس پس‌زمینه را خودکار راه‌اندازی کن.
        if (ScreenTimeService.isMonitoringEnabled(applicationContext)) {
            startScreenTimeServiceIfNeeded()
        }
        requestNotificationPermissionIfNeeded()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRealScreenTimeSeconds" -> {
                        val seconds = ScreenTimeService.getCurrentTotalSeconds(applicationContext)
                        result.success(seconds)
                    }
                    "resetScreenTime" -> {
                        ScreenTimeService.resetToday(applicationContext)
                        result.success(true)
                    }
                    "setAppForeground" -> {
                        val foreground = call.argument<Boolean>("foreground") ?: true
                        ScreenTimeService.setAppForeground(applicationContext, foreground)
                        result.success(true)
                    }
                    "setBreakSettings" -> {
                        val shortMin = call.argument<Int>("shortIntervalMinutes") ?: 20
                        val longMin = call.argument<Int>("longIntervalMinutes") ?: 120
                        ScreenTimeService.setBreakSettings(applicationContext, shortMin, longMin)
                        result.success(true)
                    }
                    "setNextBreakThresholds" -> {
                        val shortAt = (call.argument<Int>("nextShortAtSeconds") ?: 1200).toLong()
                        val longAt = (call.argument<Int>("nextLongAtSeconds") ?: 7200).toLong()
                        ScreenTimeService.setNextBreakThresholds(applicationContext, shortAt, longAt)
                        result.success(true)
                    }
                    "getNextBreakThresholds" -> {
                        val thresholds = ScreenTimeService.getNextBreakThresholds(applicationContext)
                        result.success(
                            mapOf(
                                "nextShortAtSeconds" to thresholds.first,
                                "nextLongAtSeconds" to thresholds.second
                            )
                        )
                    }
                    "setMonitoringEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        ScreenTimeService.setMonitoringEnabled(applicationContext, enabled)
                        result.success(true)
                    }
                    "setVoiceAlertsEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        ScreenTimeService.setVoiceAlertsEnabled(applicationContext, enabled)
                        result.success(true)
                    }
                    "stopMonitoringService" -> {
                        // توقف کامل سرویس پس‌زمینه؛ نوتیفیکیشن دائمی هم حذف می‌شود
                        // و دیگر واقعاً هیچ چیزی از این اپ در پس‌زمینه نمی‌ماند.
                        val stopIntent = Intent(this, ScreenTimeService::class.java)
                        stopService(stopIntent)
                        result.success(true)
                    }
                    "startMonitoringService" -> {
                        startScreenTimeServiceIfNeeded()
                        result.success(true)
                    }
                    "showBreakFinishedNotification" -> {
                        ScreenTimeService.showStandaloneNotification(
                            applicationContext,
                            1004,
                            "🔔 استراحت تمام شد",
                            "می‌توانی به کار خودت ادامه بدهی."
                        )
                        ScreenTimeService.speakOnce(applicationContext, "استراحت تمام شد، می‌تونی ادامه بدی")
                        result.success(true)
                    }
                    "setBlinkSettings" -> {
                        val intervalMin = call.argument<Int>("intervalMinutes") ?: 5
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        ScreenTimeService.setBlinkSettings(applicationContext, intervalMin, enabled)
                        result.success(true)
                    }
                    "checkOverlayPermission" -> {
                        result.success(ScreenTimeService.canDrawOverlay(applicationContext))
                    }
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                android.net.Uri.parse("package:$packageName")
                            )
                            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "stopScreenTimeService" -> {
                        // این فقط نوتیفیکیشن‌ها را متوقف نمی‌کند، خودِ سرویس
                        // پس‌زمینه را کامل می‌بندد (نوتیفیکیشن پایدار هم حذف می‌شود).
                        val serviceIntent = Intent(this, ScreenTimeService::class.java)
                        stopService(serviceIntent)
                        result.success(true)
                    }
                    "startScreenTimeService" -> {
                        startScreenTimeServiceIfNeeded()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startScreenTimeServiceIfNeeded() {
        val serviceIntent = Intent(this, ScreenTimeService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    notificationPermissionRequestCode
                )
            }
        }
    }
}
