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
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * سرویس Foreground که مستقل از حیات صفحه‌ی Flutter اجرا می‌شود.
 * وظایف:
 *   ۱) ردیابی مجموع زمان واقعی روشن‌بودن صفحه‌ی گوشی با گوش‌دادن به
 *      ACTION_SCREEN_ON/OFF.
 *   ۲) وقتی اپ در پس‌زمینه است، هر ۶۰ ثانیه بررسی می‌کند که آیا آستانه‌ی
 *      پلک‌زدن/استراحت کوتاه/استراحت طولانی رد شده یا نه.
 *   ۳) اگر مجوز «نمایش روی اپ‌های دیگر» داده شده باشد، یادآوری‌ها را با
 *      یک overlay واقعی روی هر اپی که کاربر در حال استفاده از آن است
 *      نشان می‌دهد؛ در غیر این صورت با نوتیفیکیشن معمولی fallback می‌کند.
 */
class ScreenTimeService : Service() {

    private lateinit var prefs: SharedPreferences
    private var screenReceiver: BroadcastReceiver? = null
    private val handler = Handler(Looper.getMainLooper())
    private var checkRunnable: Runnable? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    /** خواندن متن با صدا (فارسی)؛ اگر موتور TTS گوشی زبان فارسی را
     *  پشتیبانی نکند یا آماده نباشد، بی‌خطر نادیده گرفته می‌شود — هیچ‌وقت
     *  مانع نمایش خودِ نوتیفیکیشن نمی‌شود. */
    private fun speak(text: String) {
        try {
            val voiceEnabled = prefs.getBoolean("voiceAlertsEnabled", true)
            if (!voiceEnabled || !ttsReady || tts == null) return
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "eyecare_tts")
        } catch (e: Exception) {
            // بی‌خطر رد شو
        }
    }

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
        const val DEFAULT_BLINK_MINUTES = 5

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
                val blinkMin = prefs.getInt("blinkIntervalMinutes", DEFAULT_BLINK_MINUTES)
                prefs.edit()
                    .putLong("totalMillis", 0L)
                    .putString("date", today)
                    .putLong("nextShortAtSeconds", (shortMin * 60).toLong())
                    .putLong("nextLongAtSeconds", (longMin * 60).toLong())
                    .putLong("nextBlinkAtSeconds", (blinkMin * 60).toLong())
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

        fun setBlinkSettings(context: Context, intervalMinutes: Int, enabled: Boolean) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putInt("blinkIntervalMinutes", intervalMinutes)
                .putBoolean("blinkReminderEnabled", enabled)
                .apply()
        }

        fun canDrawOverlay(context: Context): Boolean {
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                Settings.canDrawOverlays(context)
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

        fun setVoiceAlertsEnabled(context: Context, enabled: Boolean) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putBoolean("voiceAlertsEnabled", enabled).apply()
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
                .setTimeoutAfter(20_000)
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

        /** یک بار کوتاه صحبت می‌کند (برای نوتیفیکیشن‌های مستقل مثل پایان
         *  استراحت که نمونه‌ی در حال اجرای سرویس را در اختیار ندارند)؛
         *  یک موتور TTS موقت می‌سازد و بعد از چند ثانیه خودش را می‌بندد. */
        fun speakOnce(context: Context, text: String) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                if (!prefs.getBoolean("voiceAlertsEnabled", true)) return
                var engine: TextToSpeech? = null
                engine = TextToSpeech(context) { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        val result = engine?.setLanguage(Locale("fa", "IR"))
                        if (result != TextToSpeech.LANG_MISSING_DATA &&
                            result != TextToSpeech.LANG_NOT_SUPPORTED
                        ) {
                            engine?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "eyecare_tts_once")
                        }
                    }
                    Handler(Looper.getMainLooper()).postDelayed({
                        try {
                            engine?.stop()
                            engine?.shutdown()
                        } catch (e: Exception) {
                        }
                    }, 4000)
                }
            } catch (e: Exception) {
                // بی‌خطر رد شو
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
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID_PERSISTENT,
            buildPersistentNotification(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            else
                0
        )
        startPeriodicBreakCheck()

        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts?.setLanguage(Locale("fa", "IR"))
                ttsReady = result != TextToSpeech.LANG_MISSING_DATA &&
                    result != TextToSpeech.LANG_NOT_SUPPORTED
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    /** اگر کاربر از تنظیمات، «فعال بودن برنامه» را خاموش کرده باشد، و
     *  سیستم به هر دلیلی بخواهد سرویس را زنده نگه دارد، همینجا کاملاً
     *  متوقفش می‌کنیم تا واقعاً هیچ چیزی در پس‌زمینه نماند. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val monitoringEnabled = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean("monitoringEnabled", true)
        if (!monitoringEnabled) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
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
     * فقط وقتی اپ در پس‌زمینه است بررسی می‌کند؛ وقتی اپ باز است، Flutter
     * خودش با دیالوگ/انیمیشن داخل‌اپ این کار را انجام می‌دهد.
     * برای هرکدام از پلک‌زدن/استراحت کوتاه/استراحت طولانی: اگر مجوز
     * overlay داده شده باشد، مستقیماً روی صفحه (روی هر اپی که باز است)
     * نمایش داده می‌شود؛ در غیر این صورت با نوتیفیکیشن fallback می‌کند.
     */
    private fun checkBreakThresholds() {
        ensureFreshDay(prefs)
        val monitoringEnabled = prefs.getBoolean("monitoringEnabled", true)
        if (!monitoringEnabled) return
        val appInForeground = prefs.getBoolean("appInForeground", true)
        if (appInForeground) return

        val currentTotal = getCurrentTotalSeconds(this)
        val overlayAllowed = canDrawOverlay(this)

        // پلک‌زدن
        val blinkEnabled = prefs.getBoolean("blinkReminderEnabled", true)
        if (blinkEnabled) {
            val blinkMin = prefs.getInt("blinkIntervalMinutes", DEFAULT_BLINK_MINUTES)
            val nextBlinkAt = prefs.getLong("nextBlinkAtSeconds", (blinkMin * 60).toLong())
            if (currentTotal >= nextBlinkAt) {
                if (overlayAllowed) {
                    handler.post { showBlinkOverlay() }
                } else {
                    showBreakNotification(1005, "👁️ پلک بزن", "چند بار پلک بزن تا چشم‌هایت خشک نشود.")
                }
                speak("پلک بزن")
                prefs.edit().putLong("nextBlinkAtSeconds", currentTotal + blinkMin * 60L).apply()
            }
        }

        // استراحت کوتاه (۲۰-۲۰-۲۰)
        val shortAt = prefs.getLong("nextShortAtSeconds", (DEFAULT_SHORT_MINUTES * 60).toLong())
        val shortMin = prefs.getInt("shortIntervalMinutes", DEFAULT_SHORT_MINUTES)
        if (currentTotal >= shortAt) {
            if (overlayAllowed) {
                handler.post { showBreakOverlay(isLong = false) }
            } else {
                showBreakNotification(
                    NOTIFICATION_ID_SHORT_BREAK,
                    "👁️ وقت مراقبت از چشم",
                    "۲۰ ثانیه به فاصله‌ی حداقل ۶ متر نگاه کن."
                )
            }
            speak("بیست ثانیه به فاصله شش متر نگاه کن")
            prefs.edit().putLong("nextShortAtSeconds", currentTotal + shortMin * 60L).apply()
        }

        // استراحت طولانی
        val longAt = prefs.getLong("nextLongAtSeconds", (DEFAULT_LONG_MINUTES * 60).toLong())
        val longMin = prefs.getInt("longIntervalMinutes", DEFAULT_LONG_MINUTES)
        if (currentTotal >= longAt) {
            if (overlayAllowed) {
                handler.post { showBreakOverlay(isLong = true) }
            } else {
                showBreakNotification(
                    NOTIFICATION_ID_LONG_BREAK,
                    "🛑 استراحت طولانی",
                    "مدت زیادی از صفحه استفاده کردی؛ ۱۵ دقیقه مانیتور را رها کن، برای سلامت چشم‌های قشنگت 💙"
                )
            }
            speak("پانزده دقیقه مانیتور را رها کن، برای سلامت چشمای قشنگت")
            prefs.edit().putLong("nextLongAtSeconds", currentTotal + longMin * 60L).apply()
        }
    }

    // ==================== نمایش Overlay روی سایر اپ‌ها ====================

    private var overlayView: View? = null
    private val windowManager by lazy { getSystemService(Context.WINDOW_SERVICE) as WindowManager }

    private fun removeOverlay() {
        val v = overlayView ?: return
        try {
            windowManager.removeView(v)
        } catch (e: Exception) {
            // احتمالاً از قبل حذف شده؛ مشکلی نیست
        }
        overlayView = null
    }

    private fun overlayWindowType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
    }

    /** حباب کوچک یادآوری پلک‌زدن؛ با لمس («فهمیدم و انجام دادم») بسته
     *  می‌شود، و در صورت لمس‌نشدن، خودش بعد از چند ثانیه محو می‌شود. */
    private fun showBlinkOverlay() {
        if (!canDrawOverlay(this)) return
        removeOverlay()

        val density = resources.displayMetrics.density
        val sizePx = (72 * density).toInt()

        val bubble = FrameLayout(this)
        val bg = GradientDrawable()
        bg.shape = GradientDrawable.OVAL
        bg.setColor(Color.WHITE)
        bubble.background = bg
        bubble.elevation = (8 * density)

        val icon = ImageView(this)
        icon.setImageResource(R.drawable.ic_blink)
        val iconPadding = (6 * density).toInt()
        icon.setPadding(iconPadding, iconPadding, iconPadding, iconPadding)
        bubble.addView(icon, FrameLayout.LayoutParams(sizePx, sizePx))

        bubble.setOnClickListener { removeOverlay() }

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.END
        params.x = (12 * density).toInt()
        params.y = (100 * density).toInt()

        try {
            windowManager.addView(bubble, params)
            overlayView = bubble
            // اگر کاربر لمس نکرد، خودش بعد از ۴ ثانیه محو شود تا مزاحم نشود
            handler.postDelayed({
                if (overlayView == bubble) removeOverlay()
            }, 4000)
        } catch (e: Exception) {
            // اگر افزودن overlay به هر دلیلی شکست خورد (مثلاً مجوز لغو شده)، بی‌خطر رد شو
        }
    }

    /** کارت شناور سؤال استراحت (کوتاه یا طولانی) روی هر اپی که باز است،
     *  دقیقاً با همان گزینه‌های داخل‌اپ: الان / ۵ دقیقه بعد / ۱۰ دقیقه بعد / لغو. */
    private fun showBreakOverlay(isLong: Boolean) {
        if (!canDrawOverlay(this)) return
        removeOverlay()

        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val card = LinearLayout(this)
        card.orientation = LinearLayout.VERTICAL
        card.setPadding(dp(24), dp(24), dp(24), dp(16))
        val cardBg = GradientDrawable()
        cardBg.setColor(Color.WHITE)
        cardBg.cornerRadius = dp(20).toFloat()
        card.background = cardBg
        card.elevation = dp(12).toFloat()

        val titleView = TextView(this)
        titleView.text = if (isLong) "🛑 استراحت طولانی" else "👁️ وقت مراقبت از چشم"
        titleView.textSize = 17f
        titleView.setTypeface(null, Typeface.BOLD)
        titleView.gravity = Gravity.CENTER
        titleView.setTextColor(Color.parseColor("#1A202C"))
        card.addView(titleView)

        val msgView = TextView(this)
        msgView.text = if (isLong)
            "پیشنهاد می‌کنیم ۱۵ دقیقه از صفحه فاصله بگیری."
        else
            "آیا حداقل ۶ متر به دور نگاه می‌کنی؟"
        msgView.textSize = 14f
        msgView.gravity = Gravity.CENTER
        msgView.setPadding(0, dp(10), 0, dp(18))
        msgView.setTextColor(Color.parseColor("#4A5568"))
        card.addView(msgView)

        val currentTotal = getCurrentTotalSeconds(this)
        val shortMin = prefs.getInt("shortIntervalMinutes", DEFAULT_SHORT_MINUTES)
        val longMin = prefs.getInt("longIntervalMinutes", DEFAULT_LONG_MINUTES)

        fun postponeSeconds(minutes: Int) {
            val key = if (isLong) "nextLongAtSeconds" else "nextShortAtSeconds"
            prefs.edit().putLong(key, currentTotal + minutes * 60L).apply()
        }

        fun addOverlayButton(text: String, primary: Boolean, onTap: () -> Unit) {
            val btn = Button(this)
            btn.text = text
            btn.isAllCaps = false
            btn.textSize = 14f
            if (primary) {
                btn.setTextColor(Color.WHITE)
                val btnBg = GradientDrawable()
                btnBg.setColor(Color.parseColor("#2B6CB0"))
                btnBg.cornerRadius = dp(12).toFloat()
                btn.background = btnBg
            } else {
                btn.setTextColor(Color.parseColor("#2B6CB0"))
                btn.setBackgroundColor(Color.TRANSPARENT)
            }
            btn.setOnClickListener {
                onTap()
                removeOverlay()
            }
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(44)
            )
            lp.topMargin = dp(8)
            card.addView(btn, lp)
        }

        if (isLong) {
            addOverlayButton("الان استراحت می‌کنم", true) {
                // کاربر خودش استراحت را انجام می‌دهد؛ فقط کارت بسته می‌شود
            }
        } else {
            // برای استراحت کوتاه، «الان انجام می‌دهم» باید مثل حالت داخل‌اپ
            // یک شمارش معکوس ۲۰ ثانیه‌ای واقعی نشان بدهد، نه فقط بسته شود.
            val primaryBtn = Button(this)
            primaryBtn.text = "الان انجام می‌دهم"
            primaryBtn.isAllCaps = false
            primaryBtn.textSize = 14f
            primaryBtn.setTextColor(Color.WHITE)
            val primaryBg = GradientDrawable()
            primaryBg.setColor(Color.parseColor("#2B6CB0"))
            primaryBg.cornerRadius = dp(12).toFloat()
            primaryBtn.background = primaryBg
            primaryBtn.setOnClickListener {
                showCountdownOverlay()
            }
            val primaryLp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(44)
            )
            primaryLp.topMargin = dp(8)
            card.addView(primaryBtn, primaryLp)
        }
        addOverlayButton("۵ دقیقه بعد", false) { postponeSeconds(5) }
        addOverlayButton("۱۰ دقیقه بعد", false) { postponeSeconds(10) }
        addOverlayButton("لغو", false) { postponeSeconds(if (isLong) longMin else shortMin) }

        val params = WindowManager.LayoutParams(
            dp(300),
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER

        try {
            windowManager.addView(card, params)
            overlayView = card
        } catch (e: Exception) {
            // اگر افزودن overlay شکست خورد، بی‌خطر رد شو (نوتیفیکیشن fallback از قبل نرفته چون این مسیر جدا از آن است)
        }
    }

    /** شمارش معکوس ۲۰ ثانیه‌ای روی هر اپی که باز است (معادل overlay همان
     *  دیالوگ داخل‌اپ)؛ در پایان هم نوتیفیکیشن و هم صدای «تمام شد» را
     *  فعال می‌کند تا کاربر واقعاً متوجه پایان استراحت بشود. */
    private fun showCountdownOverlay() {
        removeOverlay()
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val card = LinearLayout(this)
        card.orientation = LinearLayout.VERTICAL
        card.gravity = Gravity.CENTER
        card.setPadding(dp(28), dp(28), dp(28), dp(28))
        val cardBg = GradientDrawable()
        cardBg.setColor(Color.WHITE)
        cardBg.cornerRadius = dp(20).toFloat()
        card.background = cardBg
        card.elevation = dp(12).toFloat()

        val titleView = TextView(this)
        titleView.text = "نگاه به فاصله ۶ متری"
        titleView.textSize = 15f
        titleView.setTypeface(null, Typeface.BOLD)
        titleView.gravity = Gravity.CENTER
        titleView.setTextColor(Color.parseColor("#1A202C"))
        card.addView(titleView)

        val countView = TextView(this)
        countView.textSize = 44f
        countView.setTypeface(null, Typeface.BOLD)
        countView.gravity = Gravity.CENTER
        countView.setTextColor(Color.parseColor("#2B6CB0"))
        countView.setPadding(0, dp(12), 0, dp(4))
        card.addView(countView)

        val subView = TextView(this)
        subView.text = "ثانیه باقی‌مانده"
        subView.textSize = 12f
        subView.gravity = Gravity.CENTER
        subView.setTextColor(Color.parseColor("#4A5568"))
        card.addView(subView)

        val params = WindowManager.LayoutParams(
            dp(220),
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER

        try {
            windowManager.addView(card, params)
            overlayView = card
        } catch (e: Exception) {
            return
        }

        var secondsLeft = 20
        countView.text = secondsLeft.toString()
        val tickRunnable = object : Runnable {
            override fun run() {
                secondsLeft--
                if (secondsLeft <= 0) {
                    if (overlayView == card) removeOverlay()
                    showStandaloneNotification(
                        this@ScreenTimeService,
                        1004,
                        "🔔 استراحت تمام شد",
                        "می‌توانی به کار خودت ادامه بدهی."
                    )
                    speak("استراحت تمام شد، می‌تونی ادامه بدی")
                    return
                }
                if (overlayView == card) {
                    countView.text = secondsLeft.toString()
                    handler.postDelayed(this, 1000)
                }
            }
        }
        handler.postDelayed(tickRunnable, 1000)
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
            .setTimeoutAfter(5 * 60_000)
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
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (e: Exception) {
            // بی‌خطر رد شو
        }
        super.onDestroy()
    }
}
