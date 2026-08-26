package com.example.eyecare

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * سرویس Foreground که مستقل از حیات صفحه‌ی Flutter اجرا می‌شود.
 * دو وظیفه دارد:
 *   ۱) ردیابی مجموع زمان واقعی روشن‌بودن صفحه‌ی گوشی (صرف‌نظر از این‌که
 *      کدام اپ باز است) با گوش‌دادن به ACTION_SCREEN_ON/OFF.
 *   ۲) وقتی اپ در پس‌زمینه است، هر ۶۰ ثانیه بررسی می‌کند که آیا آستانه‌ی
 *      استراحت کوتاه/طولانی رد شده یا نه؛ اگر رد شده، یک نوتیفیکیشن واقعی
 *      اندروید می‌فرستد (چون دیالوگ داخل‌اپ در پس‌زمینه دیده نمی‌شود).
 */
class ScreenTimeService : Service() {

    private lateinit var prefs: SharedPreferences
    private var screenReceiver: BroadcastReceiver? = null
    private val handler = Handler(Looper.getMainLooper())
    private var checkRunnable: Runnable? = null

    companion object {
        const val PREFS_NAME = "eyecare_native_screen_time"
        const val CHANNEL_ID_PERSISTENT = "eyecare_screen_time_channel"
        const val CHANNEL_ID_BREAK = "eyecare_break_alerts_channel"
        const val NOTIFICATION_ID_PERSISTENT = 1001
        const val NOTIFICATION_ID_SHORT_BREAK = 1002
        const val NOTIFICATION_ID_LONG_BREAK = 1003
        const val CHECK_INTERVAL_MILLIS = 60_000L
        const val DEFAULT_SHORT_MINUTES = 20
        const val DEFAULT_LONG_MINUTES = 120

        private fun todayKey(): String {
            val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            return fmt.format(Date())
        }

        private fun ensureFreshDay(prefs: SharedPreferences) {
            val savedDate = prefs.getString("date", null)
            val today = todayKey()
            if (savedDate != today) {
                val shortMin = prefs.getInt("shortIntervalMinutes", DEFAULT_SHORT_MINUTES)
                val longMin = prefs.getInt("longIntervalMinutes", DEFAULT_LONG_MINUTES)
                prefs.edit()
                    .putLong("totalMillis", 0L)
                    .putString("date", today)
                    .putLong("nextShortAtSeconds", (shortMin * 60).toLong())
                    .putLong("nextLongAtSeconds", (longMin * 60).toLong())
                    .apply()
            }
        }

        /** مجموع ثانیه‌های واقعی روشن‌بودن صفحه‌ی امروز. */
        fun getCurrentTotalSeconds(context: Context): Long {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            ensureFreshDay(prefs)
            val totalMillis = prefs.getLong("totalMillis", 0L)
            val isScreenOn = prefs.getBoolean("isScreenOn", false)
            val sessionStart = prefs.getLong("sessionStartMillis", 0L)
            val currentSession = if (isScreenOn && sessionStart > 0L) {
                System.currentTimeMillis() - sessionStart
            } else {
                0L
            }
            return (totalMillis + currentSession) / 1000
        }

        fun resetToday(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val isOn = powerManager.isInteractive
            val shortMin = prefs.getInt("shortIntervalMinutes", DEFAULT_SHORT_MINUTES)
            val longMin = prefs.getInt("longIntervalMinutes", DEFAULT_LONG_MINUTES)
            prefs.edit()
                .putLong("totalMillis", 0L)
                .putString("date", todayKey())
                .putBoolean("isScreenOn", isOn)
                .putLong("sessionStartMillis", if (isOn) System.currentTimeMillis() else 0L)
                .putLong("nextShortAtSeconds", (shortMin * 60).toLong())
                .putLong("nextLongAtSeconds", (longMin * 60).toLong())
                .apply()
        }

        fun setAppForeground(context: Context, foreground: Boolean) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean("appInForeground", foreground).apply()
        }

        fun setBreakSettings(context: Context, shortIntervalMinutes: Int, longIntervalMinutes: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putInt("shortIntervalMinutes", shortIntervalMinutes)
                .putInt("longIntervalMinutes", longIntervalMinutes)
                .apply()
        }

        fun setNextBreakThresholds(context: Context, nextShortAtSeconds: Long, nextLongAtSeconds: Long) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putLong("nextShortAtSeconds", nextShortAtSeconds)
                .putLong("nextLongAtSeconds", nextLongAtSeconds)
                .apply()
        }

        fun getNextBreakThresholds(context: Context): Pair<Long, Long> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            ensureFreshDay(prefs)
            val shortAt = prefs.getLong("nextShortAtSeconds", (DEFAULT_SHORT_MINUTES * 60).toLong())
            val longAt = prefs.getLong("nextLongAtSeconds", (DEFAULT_LONG_MINUTES * 60).toLong())
            return Pair(shortAt, longAt)
        }

        /** کلید روشن/خاموش کامل مانیتورینگ؛ اگر خاموش باشد، سرویس هیچ
         *  نوتیفیکیشن استراحتی نمی‌فرستد (حتی اگر آستانه رد شده باشد). */
        fun setMonitoringEnabled(context: Context, enabled: Boolean) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean("monitoringEnabled", enabled).apply()
        }

        fun isMonitoringEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return prefs.getBoolean("monitoringEnabled", true)
        }

        /** یک نوتیفیکیشن ساده و مستقل (مثلاً پیام پایان شمارش معکوس ۲۰
         *  ثانیه‌ای) بدون وابستگی به نمونه‌ی در حال اجرای سرویس. از همان
         *  کانال CHANNEL_ID_BREAK استفاده می‌کند که در onCreate ساخته
         *  می‌شود؛ اگر سرویس هنوز یک‌بار هم اجرا نشده باشد این کانال ممکن
         *  است وجود نداشته باشد، برای همین اینجا هم دوباره (idempotent)
         *  ساخته می‌شود. */
        fun showStandaloneNotification(context: Context, id: Int, title: String, text: String) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val manager = context.getSystemService(NotificationManager::class.java)
                val channel = NotificationChannel(
                    CHANNEL_ID_BREAK,
                    "یادآوری‌های استراحت چشم",
                    NotificationManager.IMPORTANCE_HIGH
                )
                manager?.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(context, CHANNEL_ID_BREAK)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_view)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED

            if (hasPermission) {
                NotificationManagerCompat.from(context).notify(id, notification)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        ensureFreshDay(prefs)
        initializeScreenState()
        registerScreenReceiver()
        createNotificationChannels()
        startForeground(NOTIFICATION_ID_PERSISTENT, buildPersistentNotification())
        startPeriodicBreakCheck()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    private fun initializeScreenState() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        val isOn = powerManager.isInteractive
        val editor = prefs.edit()
        editor.putBoolean("isScreenOn", isOn)
        if (isOn) {
            editor.putLong("sessionStartMillis", System.currentTimeMillis())
        }
        editor.apply()
    }

    private fun registerScreenReceiver() {
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                ensureFreshDay(prefs)
                when (intent?.action) {
                    Intent.ACTION_SCREEN_ON -> {
                        prefs.edit()
                            .putBoolean("isScreenOn", true)
                            .putLong("sessionStartMillis", System.currentTimeMillis())
                            .apply()
                    }
                    Intent.ACTION_SCREEN_OFF -> {
                        val isScreenOn = prefs.getBoolean("isScreenOn", false)
                        val sessionStart = prefs.getLong("sessionStartMillis", 0L)
                        if (isScreenOn && sessionStart > 0L) {
                            val elapsed = System.currentTimeMillis() - sessionStart
                            val totalMillis = prefs.getLong("totalMillis", 0L)
                            prefs.edit()
                                .putLong("totalMillis", totalMillis + elapsed)
                                .putBoolean("isScreenOn", false)
                                .putLong("sessionStartMillis", 0L)
                                .apply()
                        }
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, filter)
    }

    private fun startPeriodicBreakCheck() {
        checkRunnable = object : Runnable {
            override fun run() {
                checkBreakThresholds()
                handler.postDelayed(this, CHECK_INTERVAL_MILLIS)
            }
        }
        handler.postDelayed(checkRunnable!!, CHECK_INTERVAL_MILLIS)
    }

    /**
     * فقط وقتی اپ در پس‌زمینه است نوتیفیکیشن می‌فرستد؛ وقتی اپ باز است،
     * Flutter خودش با دیالوگ داخل‌اپ این کار را انجام می‌دهد و اینجا هیچ
     * کاری نمی‌کنیم تا دوبار یادآوری نشود.
     */
    private fun checkBreakThresholds() {
        ensureFreshDay(prefs)
        val monitoringEnabled = prefs.getBoolean("monitoringEnabled", true)
        if (!monitoringEnabled) return
        val appInForeground = prefs.getBoolean("appInForeground", true)
        if (appInForeground) return

        val currentTotal = getCurrentTotalSeconds(this)
        val shortAt = prefs.getLong("nextShortAtSeconds", (DEFAULT_SHORT_MINUTES * 60).toLong())
        val longAt = prefs.getLong("nextLongAtSeconds", (DEFAULT_LONG_MINUTES * 60).toLong())
        val shortMin = prefs.getInt("shortIntervalMinutes", DEFAULT_SHORT_MINUTES)
        val longMin = prefs.getInt("longIntervalMinutes", DEFAULT_LONG_MINUTES)

        if (currentTotal >= shortAt) {
            showBreakNotification(
                NOTIFICATION_ID_SHORT_BREAK,
                "👁️ وقت مراقبت از چشم",
                "آیا حداقل ۶ متر به دور نگاه می‌کنی؟"
            )
            prefs.edit().putLong("nextShortAtSeconds", currentTotal + shortMin * 60L).apply()
        }
        if (currentTotal >= longAt) {
            showBreakNotification(
                NOTIFICATION_ID_LONG_BREAK,
                "🛑 استراحت طولانی",
                "پیشنهاد می‌کنیم ۱۵ دقیقه از صفحه فاصله بگیری."
            )
            prefs.edit().putLong("nextLongAtSeconds", currentTotal + longMin * 60L).apply()
        }
    }

    private fun showBreakNotification(id: Int, title: String, text: String) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID_BREAK)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val hasPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED

        if (hasPermission) {
            NotificationManagerCompat.from(this).notify(id, notification)
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            val persistentChannel = NotificationChannel(
                CHANNEL_ID_PERSISTENT,
                "پایش زمان صفحه",
                NotificationManager.IMPORTANCE_MIN
            )
            persistentChannel.description = "پایش غیرفعال زمان روشن بودن صفحه"
            manager?.createNotificationChannel(persistentChannel)

            val breakChannel = NotificationChannel(
                CHANNEL_ID_BREAK,
                "یادآوری‌های استراحت چشم",
                NotificationManager.IMPORTANCE_HIGH
            )
            breakChannel.description = "یادآوری استراحت کوتاه و بلند برای مراقبت از چشم"
            manager?.createNotificationChannel(breakChannel)
        }
    }

    private fun buildPersistentNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID_PERSISTENT)
            .setContentTitle("همراه سلامت چشم")
            .setContentText("در حال پایش زمان استفاده از صفحه")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        val isScreenOn = prefs.getBoolean("isScreenOn", false)
        val sessionStart = prefs.getLong("sessionStartMillis", 0L)
        if (isScreenOn && sessionStart > 0L) {
            val elapsed = System.currentTimeMillis() - sessionStart
            val totalMillis = prefs.getLong("totalMillis", 0L)
            prefs.edit().putLong("totalMillis", totalMillis + elapsed).apply()
        }
        checkRunnable?.let { handler.removeCallbacks(it) }
        screenReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // قبلاً unregister شده؛ مشکلی نیست
            }
        }
        super.onDestroy()
    }
}
