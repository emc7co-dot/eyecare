import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'native_screen_time_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const EyeCareApp());
}

class EyeCareApp extends StatelessWidget {
  const EyeCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محافظ چشم',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B6CB0),
          brightness: Brightness.light,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const MainDashboard(),
    );
  }
}

// ==================== وضعیت «زمان واقعی استفاده» و یادآوری پس‌زمینه ====================
// اندروید: زمان واقعی روشن‌بودن صفحه از یک Foreground Service بومی خوانده
// می‌شود (ScreenTimeService.kt) که مستقل از حیات این ویجت کار می‌کند و حتی
// وقتی کاربر در اپ دیگری است، با نوتیفیکیشن یادآوری استراحت کوتاه/طولانی
// می‌فرستد (یادآوری پلک و بررسی فاصله عمداً فقط داخل‌اپ‌اند، چون معنای
// «نگاه کردن به این اپ» را دارند و نمایش آن‌ها روی اپ دیگر نیاز به
// دسترسی overlay دارد که این پروژه عمداً از آن استفاده نمی‌کند).
//
// iOS: این کانال بومی پیاده نشده (Screen Time API اپل نیازمند entitlement
// خاص است)؛ در iOS به‌صورت خودکار به شمارش محلی foreground-only برمی‌گردیم.
// این محدودیت با فلگ _nativeAvailable مدیریت می‌شود، نه با وانمود کردن به
// این‌که حل شده است.
// ================================================================================

class EyeCareSettings {
  bool blinkReminderEnabled;
  int blinkIntervalMinutes;
  int shortBreakIntervalMinutes;
  int longBreakIntervalMinutes;
  bool strictLockMode;
  bool monitoringEnabled;
  bool voiceAlertsEnabled;
  bool isPaidVersion;

  EyeCareSettings({
    this.blinkReminderEnabled = true,
    this.blinkIntervalMinutes = 5,
    this.shortBreakIntervalMinutes = 20,
    this.longBreakIntervalMinutes = 120,
    this.strictLockMode = false,
    this.monitoringEnabled = true,
    this.voiceAlertsEnabled = true,
    this.isPaidVersion = false,
  });

  factory EyeCareSettings.fromPrefs(SharedPreferences p) => EyeCareSettings(
        blinkReminderEnabled: p.getBool('blinkReminderEnabled') ?? true,
        blinkIntervalMinutes: p.getInt('blinkIntervalMinutes') ?? 5,
        shortBreakIntervalMinutes: p.getInt('shortBreakIntervalMinutes') ?? 20,
        longBreakIntervalMinutes: p.getInt('longBreakIntervalMinutes') ?? 120,
        strictLockMode: p.getBool('strictLockMode') ?? false,
        monitoringEnabled: p.getBool('monitoringEnabled') ?? true,
        voiceAlertsEnabled: p.getBool('voiceAlertsEnabled') ?? true,
        isPaidVersion: p.getBool('isPaidVersion') ?? false,
      );

  Future<void> saveToPrefs(SharedPreferences p) async {
    await p.setBool('blinkReminderEnabled', blinkReminderEnabled);
    await p.setInt('blinkIntervalMinutes', blinkIntervalMinutes);
    await p.setInt('shortBreakIntervalMinutes', shortBreakIntervalMinutes);
    await p.setInt('longBreakIntervalMinutes', longBreakIntervalMinutes);
    await p.setBool('strictLockMode', strictLockMode);
    await p.setBool('monitoringEnabled', monitoringEnabled);
    await p.setBool('voiceAlertsEnabled', voiceAlertsEnabled);
    await p.setBool('isPaidVersion', isPaidVersion);
  }
}

class EyeCareStats {
  int screenTimeSeconds;
  int blinkRemindersCount;
  int shortBreaksCompleted;
  int shortBreaksTotal;
  int distanceChecksCount;
  int longBreaksCompleted;
  int longBreaksTotal;
  String dateKey;

  EyeCareStats({
    this.screenTimeSeconds = 0,
    this.blinkRemindersCount = 0,
    this.shortBreaksCompleted = 0,
    this.shortBreaksTotal = 0,
    this.distanceChecksCount = 0,
    this.longBreaksCompleted = 0,
    this.longBreaksTotal = 0,
    required this.dateKey,
  });

  static String todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'screenTimeSeconds': screenTimeSeconds,
        'blinkRemindersCount': blinkRemindersCount,
        'shortBreaksCompleted': shortBreaksCompleted,
        'shortBreaksTotal': shortBreaksTotal,
        'distanceChecksCount': distanceChecksCount,
        'longBreaksCompleted': longBreaksCompleted,
        'longBreaksTotal': longBreaksTotal,
        'dateKey': dateKey,
      };

  factory EyeCareStats.fromPrefs(SharedPreferences p) {
    final today = todayKey();
    final savedDate = p.getString('dateKey');
    if (savedDate != today) {
      return EyeCareStats(dateKey: today);
    }
    return EyeCareStats(
      screenTimeSeconds: p.getInt('screenTimeSeconds') ?? 0,
      blinkRemindersCount: p.getInt('blinkRemindersCount') ?? 0,
      shortBreaksCompleted: p.getInt('shortBreaksCompleted') ?? 0,
      shortBreaksTotal: p.getInt('shortBreaksTotal') ?? 0,
      distanceChecksCount: p.getInt('distanceChecksCount') ?? 0,
      longBreaksCompleted: p.getInt('longBreaksCompleted') ?? 0,
      longBreaksTotal: p.getInt('longBreaksTotal') ?? 0,
      dateKey: today,
    );
  }

  /// مثل fromPrefs، اما اگر روز عوض شده باشد، قبل از صفر کردن آمار، یک
  /// کپی از آمار روزِ قبل را در آرشیو تاریخچه (برای گزارش هفتگی/ماهانه)
  /// ذخیره می‌کند.
  static Future<EyeCareStats> fromPrefsWithArchive(SharedPreferences p) async {
    final today = todayKey();
    final savedDate = p.getString('dateKey');
    if (savedDate != null && savedDate != today) {
      final previous = EyeCareStats(
        screenTimeSeconds: p.getInt('screenTimeSeconds') ?? 0,
        blinkRemindersCount: p.getInt('blinkRemindersCount') ?? 0,
        shortBreaksCompleted: p.getInt('shortBreaksCompleted') ?? 0,
        shortBreaksTotal: p.getInt('shortBreaksTotal') ?? 0,
        distanceChecksCount: p.getInt('distanceChecksCount') ?? 0,
        longBreaksCompleted: p.getInt('longBreaksCompleted') ?? 0,
        longBreaksTotal: p.getInt('longBreaksTotal') ?? 0,
        dateKey: savedDate,
      );
      final raw = p.getString('statsHistory');
      final List<dynamic> history = raw != null ? jsonDecode(raw) as List<dynamic> : [];
      history.removeWhere((e) => (e as Map)['dateKey'] == savedDate);
      history.add(previous.toJson());
      // فقط ۶۰ روز اخیر را نگه می‌داریم تا حجم ذخیره‌سازی محدود بماند.
      final trimmed = history.length > 60
          ? history.sublist(history.length - 60)
          : history;
      await p.setString('statsHistory', jsonEncode(trimmed));
    }
    return EyeCareStats.fromPrefs(p);
  }

  static Future<List<Map<String, dynamic>>> loadHistory(SharedPreferences p) async {
    final raw = p.getString('statsHistory');
    if (raw == null) return [];
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> saveToPrefs(SharedPreferences p) async {
    await p.setInt('screenTimeSeconds', screenTimeSeconds);
    await p.setInt('blinkRemindersCount', blinkRemindersCount);
    await p.setInt('shortBreaksCompleted', shortBreaksCompleted);
    await p.setInt('shortBreaksTotal', shortBreaksTotal);
    await p.setInt('distanceChecksCount', distanceChecksCount);
    await p.setInt('longBreaksCompleted', longBreaksCompleted);
    await p.setInt('longBreaksTotal', longBreaksTotal);
    await p.setString('dateKey', dateKey);
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  EyeCareStats _stats = EyeCareStats(dateKey: EyeCareStats.todayKey());
  EyeCareSettings _settings = EyeCareSettings();
  SharedPreferences? _prefs;
  bool _loaded = false;

  bool _nativeAvailable = false;
  bool _hasOverlayPermission = false;
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;

  // شناسه‌ی آزمایشی رسمی گوگل — همیشه یک تبلیغ نمونه نشان می‌دهد و بدون
  // حساب AdMob هم کار می‌کند. پیش از انتشار نهایی باید با Ad Unit ID
  // واقعیِ حساب AdMob خودتان جایگزین شود.
  static const String _testBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  void _loadBannerAd() {
    if (_settings.isPaidVersion) return;
    _bannerAd = BannerAd(
      adUnitId: _testBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }
  int _lastKnownTotalSeconds = 0;
  int _nextShortBreakAt = 0;
  int _nextLongBreakAt = 0;
  int _nextDistanceCheckAt = 0;
  static const int _distanceCheckIntervalSeconds = 45 * 60;

  Timer? _pollTimer;
  Timer? _uiTimer;
  Timer? _blinkTimer;

  bool _appInForeground = true;
  bool _dialogOpen = false;

  late AnimationController _blinkAnimController;
  bool _showBlinkOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _blinkAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadAndStart();
  }

  Future<void> _loadAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _settings = EyeCareSettings.fromPrefs(prefs);
    _stats = await EyeCareStats.fromPrefsWithArchive(prefs);

    final native = await NativeScreenTimeService.getRealScreenTimeSeconds();
    _nativeAvailable = native != null;
    final startSeconds = native ?? _stats.screenTimeSeconds;

    _stats.screenTimeSeconds = startSeconds;
    _lastKnownTotalSeconds = startSeconds;
    _nextShortBreakAt = startSeconds + _settings.shortBreakIntervalMinutes * 60;
    _nextLongBreakAt = startSeconds + _settings.longBreakIntervalMinutes * 60;
    _nextDistanceCheckAt = startSeconds + _distanceCheckIntervalSeconds;

    if (_nativeAvailable) {
      await NativeScreenTimeService.setBreakSettings(
        shortIntervalMinutes: _settings.shortBreakIntervalMinutes,
        longIntervalMinutes: _settings.longBreakIntervalMinutes,
      );
      await NativeScreenTimeService.setBlinkSettings(
        intervalMinutes: _settings.blinkIntervalMinutes,
        enabled: _settings.blinkReminderEnabled,
      );
      await NativeScreenTimeService.setAppForeground(true);
      await NativeScreenTimeService.setMonitoringEnabled(_settings.monitoringEnabled);
      await NativeScreenTimeService.setVoiceAlertsEnabled(_settings.voiceAlertsEnabled);
      await _syncThresholdsToNative();
      _hasOverlayPermission = await NativeScreenTimeService.checkOverlayPermission();
    }

    if (!mounted) return;
    setState(() => _loaded = true);
    if (_settings.monitoringEnabled) {
      _startTicking();
      _restartBlinkTimer();
    }
    _loadBannerAd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showMedicalDisclaimer();
    });
  }

  void _showMedicalDisclaimer() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('پیش از استفاده بخوانید'),
        content: const SingleChildScrollView(
          child: Text(
            'این برنامه یک ابزار یادآوری رفتاری برای کاهش فشار چشمی ناشی از '
            'استفاده‌ی طولانی از صفحه‌نمایش است؛ با یادآوری پلک‌زدن، استراحت‌های '
            'کوتاه و بلند و بررسی فاصله، به ایجاد عادت‌های سالم‌تر کمک می‌کند.\n\n'
            'چرا این موضوع مهم است؟\n'
            '• کار طولانی با صفحه معمولاً پلک‌زدن را کم می‌کند و می‌تواند باعث '
            'خشکی، خستگی و تاری موقت چشم شود.\n'
            '• قاعده‌ی رایج «۲۰-۲۰-۲۰» (هر ۲۰ دقیقه، ۲۰ ثانیه به فاصله‌ی حداقل ۶ '
            'متر نگاه کردن) یک توصیه‌ی شناخته‌شده برای کاهش این فشار است.\n'
            '• پژوهش‌های اخیر بین افزایش زمان استفاده از صفحه و افزایش نزدیک‌بینی '
            'ارتباط آماری نشان داده‌اند، هرچند کیفیت این شواهد هنوز محدود است و '
            'این ارتباط رابطه‌ی علّی قطعی نیست.\n\n'
            'این برنامه هیچ ادعای تشخیص، درمان یا پیشگیری قطعی از نزدیک‌بینی یا '
            'هر بیماری چشمی دیگر ندارد و جایگزین معاینه و توصیه‌ی پزشک متخصص '
            'چشم نیست. در صورت وجود هرگونه ناراحتی یا علائم چشمی، حتماً به '
            'چشم‌پزشک مراجعه کنید.',
            style: TextStyle(fontSize: 13.5, height: 1.7),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('متوجه شدم'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncThresholdsToNative() async {
    if (!_nativeAvailable) return;
    await NativeScreenTimeService.setNextBreakThresholds(
      nextShortAtSeconds: _nextShortBreakAt,
      nextLongAtSeconds: _nextLongBreakAt,
    );
  }

  void _startTicking() {
    _pollTimer?.cancel();
    _uiTimer?.cancel();
    final interval =
        _nativeAvailable ? const Duration(seconds: 5) : const Duration(seconds: 1);
    _pollTimer = Timer.periodic(interval, (_) => _tick());

    // در حالت بومی، بین دو poll (هر ۵ ثانیه)، این تایمر جداگانه هر ۱ ثانیه
    // فقط عدد نمایشی روی صفحه را +۱ می‌کند تا ثانیه‌شمار نرم دیده شود؛
    // مقدار واقعی هر ۵ ثانیه توسط _tick() با داده‌ی بومی تصحیح می‌شود.
    if (_nativeAvailable) {
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_dialogOpen || !_appInForeground || !mounted) return;
        setState(() => _stats.screenTimeSeconds++);
      });
    }
  }

  Future<void> _tick() async {
    if (_dialogOpen || !_appInForeground) return;

    int currentTotal;
    if (_nativeAvailable) {
      final native = await NativeScreenTimeService.getRealScreenTimeSeconds();
      if (native == null) return;
      currentTotal = native;
    } else {
      currentTotal = _lastKnownTotalSeconds + 1;
    }

    if (!mounted) return;
    setState(() {
      _stats.screenTimeSeconds = currentTotal;
      _lastKnownTotalSeconds = currentTotal;
    });

    if (currentTotal >= _nextShortBreakAt) {
      _stats.shortBreaksTotal++;
      _nextShortBreakAt = currentTotal + _settings.shortBreakIntervalMinutes * 60;
      _syncThresholdsToNative();
      _triggerShortBreakDialog();
      return;
    }
    if (currentTotal >= _nextLongBreakAt) {
      _stats.longBreaksTotal++;
      _nextLongBreakAt = currentTotal + _settings.longBreakIntervalMinutes * 60;
      _syncThresholdsToNative();
      _triggerLongBreakDialog();
      return;
    }
    if (currentTotal >= _nextDistanceCheckAt) {
      _nextDistanceCheckAt = currentTotal + _distanceCheckIntervalSeconds;
      _triggerDistanceCheckDialog();
      return;
    }

    if (currentTotal % 30 == 0) {
      _persistStats();
    }
  }

  void _restartBlinkTimer() {
    _blinkTimer?.cancel();
    if (!_settings.blinkReminderEnabled || !_settings.monitoringEnabled) return;
    _blinkTimer = Timer.periodic(
      Duration(minutes: _settings.blinkIntervalMinutes),
      (_) {
        if (_appInForeground && !_dialogOpen) {
          _triggerBlinkAnimation();
        }
      },
    );
  }

  /// روشن/خاموش‌کردن کل مانیتورینگ (دکمه‌ی اصلی در تنظیمات).
  /// خاموش‌کردن، خودِ سرویس پس‌زمینه‌ی اندروید را کامل می‌بندد — یعنی
  /// نوتیفیکیشن پایدار هم حذف می‌شود و اپ واقعاً دیگر در پس‌زمینه اجرا
  /// نمی‌ماند (نه فقط ساکت‌کردن یادآوری‌ها). روشن‌کردن دوباره سرویس را
  /// راه‌اندازی می‌کند.
  Future<void> _toggleMonitoring(bool enabled) async {
    _pollTimer?.cancel();
    _uiTimer?.cancel();
    _blinkTimer?.cancel();

    if (enabled) {
      if (_nativeAvailable) {
        await NativeScreenTimeService.startMonitoringService();
        await NativeScreenTimeService.setBreakSettings(
          shortIntervalMinutes: _settings.shortBreakIntervalMinutes,
          longIntervalMinutes: _settings.longBreakIntervalMinutes,
        );
        await NativeScreenTimeService.setAppForeground(true);
        await NativeScreenTimeService.setMonitoringEnabled(true);
        await _syncThresholdsToNative();
      }
      _startTicking();
      _restartBlinkTimer();
    } else {
      await NativeScreenTimeService.setMonitoringEnabled(false);
      if (_nativeAvailable) {
        await NativeScreenTimeService.stopMonitoringService();
      }
    }
  }

  Future<void> _persistStats() async {
    if (_prefs != null) await _stats.saveToPrefs(_prefs!);
  }

  Future<void> _persistSettings() async {
    if (_prefs != null) await _settings.saveToPrefs(_prefs!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _appInForeground;
    _appInForeground = state == AppLifecycleState.resumed;

    if (!_appInForeground) {
      _persistStats();
      NativeScreenTimeService.setAppForeground(false);
    } else if (!wasForeground) {
      _handleReturnToForeground();
    }
  }

  Future<void> _handleReturnToForeground() async {
    await NativeScreenTimeService.setAppForeground(true);

    final previousShortAt = _nextShortBreakAt;
    final previousLongAt = _nextLongBreakAt;

    final nativeThresholds = await NativeScreenTimeService.getNextBreakThresholds();
    bool shortBreakFiredInBackground = false;
    bool longBreakFiredInBackground = false;

    if (nativeThresholds != null) {
      final newShortAt = nativeThresholds['nextShortAtSeconds']!;
      final newLongAt = nativeThresholds['nextLongAtSeconds']!;
      // اگر آستانه‌ی جدید از قبلی بزرگ‌تر شده، یعنی سرویس بومی در نبود ما
      // یک نوتیفیکیشن فرستاده و استراحت را رد کرده — پس باید همان دیالوگ
      // را الان اینجا هم نشان بدهیم تا کاربر بتواند «الان / بعداً / لغو»
      // را انتخاب کند، نه اینکه بی‌صدا از کنارش رد شویم.
      if (newShortAt > previousShortAt) shortBreakFiredInBackground = true;
      if (newLongAt > previousLongAt) longBreakFiredInBackground = true;
      _nextShortBreakAt = newShortAt;
      _nextLongBreakAt = newLongAt;
    }

    if (!mounted) return;

    if (longBreakFiredInBackground) {
      _stats.longBreaksTotal++;
      _triggerLongBreakDialog();
    } else if (shortBreakFiredInBackground) {
      _stats.shortBreaksTotal++;
      _triggerShortBreakDialog();
    } else {
      _tick();
    }
  }

  void _triggerBlinkAnimation() {
    setState(() {
      _showBlinkOverlay = true;
      _stats.blinkRemindersCount++;
    });
    _blinkAnimController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      _blinkAnimController.reverse().then((_) {
        if (!mounted) return;
        _blinkAnimController.forward().then((_) {
          if (!mounted) return;
          _blinkAnimController.reverse().then((_) {
            if (!mounted) return;
            setState(() => _showBlinkOverlay = false);
          });
        });
      });
    });
  }

  void _triggerShortBreakDialog() {
    _dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('👁️ وقت مراقبت از چشم', textAlign: TextAlign.center),
        content: const Text(
          'آیا حداقل ۶ متر به دور نگاه می‌کنی؟',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              _startShortBreakCountdown();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('الان انجام می‌دهم'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              setState(() => _nextShortBreakAt = _lastKnownTotalSeconds + 5 * 60);
              _syncThresholdsToNative();
            },
            child: const Text('۵ دقیقه بعد'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              setState(() => _nextShortBreakAt = _lastKnownTotalSeconds + 10 * 60);
              _syncThresholdsToNative();
            },
            child: const Text('۱۰ دقیقه بعد'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              setState(() => _nextShortBreakAt =
                  _lastKnownTotalSeconds + _settings.shortBreakIntervalMinutes * 60);
              _syncThresholdsToNative();
            },
            child: const Text('لغو', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _startShortBreakCountdown() {
    _dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CountdownDialog(
        seconds: 20,
        title: 'نگاه به فاصله ۶ متری',
        onFinished: () {
          _stats.shortBreaksCompleted++;
          _persistStats();
          // نوتیفیکیشن واقعی سیستم؛ حتی اگر کاربر همون لحظه از اپ خارج
          // شده باشد یا صفحه قفل شده باشد هم دیده می‌شود، برخلاف SnackBar.
          if (_nativeAvailable) {
            NativeScreenTimeService.showBreakFinishedNotification();
          }
        },
      ),
    ).then((_) {
      _dialogOpen = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔔 استراحت تمام شد؛ می‌توانی ادامه بدهی.')),
      );
    });
  }

  void _triggerDistanceCheckDialog() {
    _dialogOpen = true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📏 بررسی فاصله صفحه'),
        content: const Text('فاصله‌ات از صفحه حداقل ۳۰ تا ۴۰ سانتی‌متر هست؟'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _stats.distanceChecksCount++);
              _persistStats();
              Navigator.pop(context);
              _dialogOpen = false;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🟢 عالی، مراقب چشم‌هایت هستی.')),
              );
            },
            child: const Text('بله'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('🔴 کمی فاصله را بیشتر کن. ممنون که مراقب چشم‌هایت هستی.')),
              );
            },
            child: const Text('نه / یادم نبود'),
          ),
        ],
      ),
    );
  }

  void _triggerLongBreakDialog() {
    _dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: !_settings.strictLockMode,
      builder: (context) => AlertDialog(
        title: const Text('🛑 استراحت طولانی'),
        content: const Text('پیشنهاد می‌کنیم ۱۵ دقیقه از صفحه فاصله بگیری.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              setState(() => _stats.longBreaksCompleted++);
              _persistStats();
              Navigator.pop(context);
              _dialogOpen = false;
            },
            child: const Text('الان استراحت می‌کنم'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              setState(() => _nextLongBreakAt = _lastKnownTotalSeconds + 5 * 60);
              _syncThresholdsToNative();
            },
            child: const Text('۵ دقیقه بعد'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              setState(() => _nextLongBreakAt = _lastKnownTotalSeconds + 10 * 60);
              _syncThresholdsToNative();
            },
            child: const Text('۱۰ دقیقه بعد'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogOpen = false;
              setState(() => _nextLongBreakAt =
                  _lastKnownTotalSeconds + _settings.longBreakIntervalMinutes * 60);
              _syncThresholdsToNative();
            },
            child: const Text('لغو'),
          ),
        ],
      ),
    );
  }

  String _statusEmoji() {
    if (_stats.shortBreaksTotal == 0) return '🟢';
    final ratio = _stats.shortBreaksCompleted / _stats.shortBreaksTotal;
    if (ratio >= 0.7) return '🟢';
    if (ratio >= 0.4) return '🟡';
    return '🔴';
  }

  String _statusText() {
    if (_stats.shortBreaksTotal == 0) {
      return 'هنوز داده‌ی کافی برای امروز ثبت نشده.';
    }
    final ratio = _stats.shortBreaksCompleted / _stats.shortBreaksTotal;
    if (ratio >= 0.7) {
      return 'امروز بخش زیادی از یادآوری‌های مراقبت از چشم را رعایت کردی.';
    }
    if (ratio >= 0.4) {
      return 'بخشی از یادآوری‌ها را رعایت کردی؛ فردا بهتر می‌شود.';
    }
    return 'امروز فرصت کمی برای رعایت یادآوری‌ها داشتی؛ فردا دوباره تلاش کن.';
  }

  Color _statusColor() {
    switch (_statusEmoji()) {
      case '🟢':
        return Colors.green;
      case '🟡':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  void _showDailyReport() {
    final hours = _stats.screenTimeSeconds ~/ 3600;
    final minutes = (_stats.screenTimeSeconds % 3600) ~/ 60;
    final color = _statusColor();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('👁️ گزارش مراقبت از چشم امروز',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('زمان استفاده از صفحه: $hours ساعت و $minutes دقیقه'),
            Text(
                'استراحت‌های ۲۰ ثانیه‌ای: ${_stats.shortBreaksCompleted} از ${_stats.shortBreaksTotal}'),
            Text('یادآوری پلک: ${_stats.blinkRemindersCount} مرتبه'),
            Text('یادآوری فاصله: ${_stats.distanceChecksCount} مرتبه'),
            Text(
                'استراحت ۱۵ دقیقه‌ای: ${_stats.longBreaksCompleted} از ${_stats.longBreaksTotal}'),
            const Divider(height: 32),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(_statusEmoji(), style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusText(),
                      style: TextStyle(color: color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// یک دیالوگ کوچک برای انتخاب بازه‌ی گزارش (روز/هفته/ماه).
  void _showReportPeriodPicker() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('گزارش کدام بازه؟'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _showDailyReport();
            },
            child: const Text('امروز'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _showPeriodReport(7, 'هفته‌ی اخیر');
            },
            child: const Text('۷ روز اخیر'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _showPeriodReport(30, 'ماه اخیر');
            },
            child: const Text('۳۰ روز اخیر'),
          ),
        ],
      ),
    );
  }

  /// گزارش تجمیعی هفتگی/ماهانه: آمار روزهای گذشته (از آرشیو) را با آمار
  /// امروز جمع می‌زند و یک جمع‌بندیِ معنادار (نه فقط عدد خام) نشان می‌دهد.
  Future<void> _showPeriodReport(int days, String periodLabel) async {
    if (_prefs == null) return;
    final history = await EyeCareStats.loadHistory(_prefs!);
    final cutoff = DateTime.now().subtract(Duration(days: days - 1));

    int totalScreenSeconds = _stats.screenTimeSeconds;
    int totalBlink = _stats.blinkRemindersCount;
    int totalShortDone = _stats.shortBreaksCompleted;
    int totalShortAll = _stats.shortBreaksTotal;
    int totalLongDone = _stats.longBreaksCompleted;
    int totalLongAll = _stats.longBreaksTotal;
    int daysWithData = _stats.screenTimeSeconds > 0 ? 1 : 0;

    for (final entry in history) {
      final dateKey = entry['dateKey'] as String?;
      if (dateKey == null) continue;
      final parts = dateKey.split('-');
      if (parts.length != 3) continue;
      final entryDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      if (entryDate.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day))) continue;

      totalScreenSeconds += (entry['screenTimeSeconds'] as num?)?.toInt() ?? 0;
      totalBlink += (entry['blinkRemindersCount'] as num?)?.toInt() ?? 0;
      totalShortDone += (entry['shortBreaksCompleted'] as num?)?.toInt() ?? 0;
      totalShortAll += (entry['shortBreaksTotal'] as num?)?.toInt() ?? 0;
      totalLongDone += (entry['longBreaksCompleted'] as num?)?.toInt() ?? 0;
      totalLongAll += (entry['longBreaksTotal'] as num?)?.toInt() ?? 0;
      daysWithData++;
    }

    final avgHoursPerDay = daysWithData > 0
        ? (totalScreenSeconds / daysWithData / 3600)
        : 0.0;
    final ratio = totalShortAll > 0 ? totalShortDone / totalShortAll : 1.0;

    String verdict;
    Color verdictColor;
    if (daysWithData == 0) {
      verdict = 'هنوز داده‌ی کافی برای این بازه ثبت نشده.';
      verdictColor = Colors.grey;
    } else if (ratio >= 0.7) {
      verdict =
          'عملکرد خوبی داشتی — در بیشتر روزهای این بازه، یادآوری‌های مراقبت از چشم را رعایت کردی.';
      verdictColor = Colors.green;
    } else if (ratio >= 0.4) {
      verdict =
          'در این بازه گاهی یادآوری‌ها رعایت شده و گاهی نه؛ سعی کن دفعه‌ی بعد پیوسته‌تر باشی.';
      verdictColor = Colors.orange;
    } else {
      verdict =
          'در این بازه بیشتر یادآوری‌ها نادیده گرفته شده‌اند؛ برای کاهش فشار چشمی بهتر است بیشتر به آن‌ها توجه کنی.';
      verdictColor = Colors.red;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('👁️ گزارش $periodLabel',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('میانگین استفاده از صفحه در روز: ${avgHoursPerDay.toStringAsFixed(1)} ساعت'),
            Text('روزهای دارای داده: $daysWithData از $days روز'),
            Text('یادآوری پلک: $totalBlink مرتبه'),
            Text('استراحت‌های کوتاه انجام‌شده: $totalShortDone از $totalShortAll'),
            Text('استراحت‌های طولانی انجام‌شده: $totalLongDone از $totalLongAll'),
            const Divider(height: 32),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: verdictColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(verdict, style: TextStyle(color: verdictColor)),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nativeAvailable
                    ? 'تنظیمات (زمان‌سنجی بومی فعال ✅ — یادآوری در پس‌زمینه فعال است)'
                    : 'تنظیمات (زمان‌سنجی محلی — فقط زمان استفاده از این اپ)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('فعال بودن برنامه',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  _settings.monitoringEnabled
                      ? 'همه‌ی یادآوری‌ها فعال است'
                      : 'برنامه غیرفعال است؛ هیچ یادآوری‌ای ارسال نمی‌شود',
                ),
                value: _settings.monitoringEnabled,
                onChanged: (v) {
                  setSheetState(() => _settings.monitoringEnabled = v);
                  setState(() {});
                  _persistSettings();
                  _toggleMonitoring(v);
                },
              ),
              const Divider(height: 24),
              ListTile(
                leading: Icon(
                  _hasOverlayPermission ? Icons.check_circle : Icons.warning_amber,
                  color: _hasOverlayPermission ? Colors.green : Colors.orange,
                ),
                title: const Text('نمایش یادآوری روی اپ‌های دیگر'),
                subtitle: Text(
                  _hasOverlayPermission
                      ? 'فعال — یادآوری‌ها حتی وقتی در اپ دیگری هستی روی صفحه نشان داده می‌شوند'
                      : 'غیرفعال — بدون این مجوز، یادآوری‌های پس‌زمینه فقط به‌صورت نوتیفیکیشن می‌آیند',
                ),
                trailing: _hasOverlayPermission
                    ? null
                    : TextButton(
                        onPressed: () async {
                          await NativeScreenTimeService.requestOverlayPermission();
                          await Future.delayed(const Duration(seconds: 1));
                          final granted =
                              await NativeScreenTimeService.checkOverlayPermission();
                          setSheetState(() => _hasOverlayPermission = granted);
                          setState(() {});
                        },
                        child: const Text('فعال‌سازی'),
                      ),
              ),
              SwitchListTile(
                title: const Text('خواندن هشدارها با صدا'),
                subtitle: const Text('وقتی اپ در پس‌زمینه است، یادآوری‌ها با صدای گوشی خوانده می‌شوند'),
                value: _settings.voiceAlertsEnabled,
                onChanged: (v) {
                  setSheetState(() => _settings.voiceAlertsEnabled = v);
                  setState(() {});
                  _persistSettings();
                  if (_nativeAvailable) {
                    NativeScreenTimeService.setVoiceAlertsEnabled(v);
                  }
                },
              ),
              const Divider(height: 24),
              SwitchListTile(
                title: const Text('یادآوری دیداری پلک زدن'),
                subtitle: const Text('انیمیشن بسیار کوتاه، بدون صدا و ویبره'),
                value: _settings.blinkReminderEnabled,
                onChanged: (v) {
                  setSheetState(() => _settings.blinkReminderEnabled = v);
                  setState(() {});
                  _persistSettings();
                  _restartBlinkTimer();
                  if (_nativeAvailable) {
                    NativeScreenTimeService.setBlinkSettings(
                      intervalMinutes: _settings.blinkIntervalMinutes,
                      enabled: _settings.blinkReminderEnabled,
                    );
                  }
                },
              ),
              ListTile(
                title: const Text('فاصله یادآوری پلک (دقیقه)'),
                subtitle: Slider(
                  min: 2,
                  max: 15,
                  divisions: 13,
                  value: _settings.blinkIntervalMinutes.toDouble(),
                  label: '${_settings.blinkIntervalMinutes}',
                  onChanged: (v) {
                    setSheetState(() => _settings.blinkIntervalMinutes = v.round());
                    setState(() {});
                    _persistSettings();
                    _restartBlinkTimer();
                    if (_nativeAvailable) {
                      NativeScreenTimeService.setBlinkSettings(
                        intervalMinutes: _settings.blinkIntervalMinutes,
                        enabled: _settings.blinkReminderEnabled,
                      );
                    }
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('حالت استراحت سخت‌گیرانه'),
                subtitle: const Text(
                    'در زمان استراحت طولانی، بستن دیالوگ با ضربه بیرون آن غیرفعال می‌شود'),
                value: _settings.strictLockMode,
                onChanged: (v) {
                  setSheetState(() => _settings.strictLockMode = v);
                  setState(() {});
                  _persistSettings();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('درباره برنامه'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('محافظ چشم',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 4),
            Text(
              'یک مداخله‌ی دیجیتال سلامت (Digital Health Intervention) برای کاهش فشار چشمی',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 12),
            Text('سازنده: احسان ایزدی'),
            SizedBox(height: 4),
            Text('وب‌سایت: Wining.ir'),
            SizedBox(height: 4),
            Text('ایمیل: ehsanizadiasl@gmail.com'),
            SizedBox(height: 4),
            Text('اینستاگرام: @Makarechian_7'),
            SizedBox(height: 12),
            Text(
              'برای پیشنهاد، گزارش مشکل یا همکاری، از راه‌های بالا با سازنده در تماس باشید.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            SizedBox(height: 16),
            Text(
              'این اپ یک ابزار یادآوری رفتاری است و هیچ‌گونه ادعای درمان یا پیشگیری قطعی از نزدیک‌بینی ندارد.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('محافظ چشم'),
        actions: [
          IconButton(icon: const Icon(Icons.bar_chart), onPressed: _showReportPeriodPicker),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showAboutDialog),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettingsSheet),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      const Color(0xFF2B6CB0),
                      const Color(0xFF63B3ED),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2B6CB0).withOpacity(0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.remove_red_eye_outlined,
                        color: Colors.white, size: 32),
                    const SizedBox(height: 8),
                    const Text('زمان فعال صفحه امروز',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(height: 8),
                    Text(
                      '${_stats.screenTimeSeconds ~/ 3600}:'
                      '${((_stats.screenTimeSeconds % 3600) ~/ 60).toString().padLeft(2, '0')}:'
                      '${(_stats.screenTimeSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _nativeAvailable
                          ? 'منبع: زمان واقعی صفحه (بومی، شامل سایر اپ‌ها)'
                          : 'منبع: تخمین محلی (فقط زمان همین اپ)',
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2B6CB0).withOpacity(0.1),
                        child: const Icon(Icons.remove_red_eye, color: Color(0xFF2B6CB0)),
                      ),
                      title: const Text('تست انیمیشن پلک زدن'),
                      trailing: const Icon(Icons.chevron_left, size: 20),
                      onTap: _triggerBlinkAnimation,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2B6CB0).withOpacity(0.1),
                        child: const Icon(Icons.timer, color: Color(0xFF2B6CB0)),
                      ),
                      title: const Text('تست یادآوری استراحت کوتاه (۲۰-۲۰-۲۰)'),
                      trailing: const Icon(Icons.chevron_left, size: 20),
                      onTap: _triggerShortBreakDialog,
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF2B6CB0).withOpacity(0.1),
                        child: const Icon(Icons.self_improvement, color: Color(0xFF2B6CB0)),
                      ),
                      title: const Text('تست یادآوری استراحت طولانی (۲ ساعت)'),
                      trailing: const Icon(Icons.chevron_left, size: 20),
                      onTap: _triggerLongBreakDialog,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_showBlinkOverlay)
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  // «فهمیدم و انجام دادم» — با لمس، بلافاصله بسته می‌شود
                  _blinkAnimController.stop();
                  setState(() => _showBlinkOverlay = false);
                },
                child: AnimatedBuilder(
                  animation: _blinkAnimController,
                  builder: (context, child) {
                    return Transform.scale(
                      scaleY: 1.0 - (_blinkAnimController.value * 0.9),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B6CB0),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2B6CB0).withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.remove_red_eye,
                            color: Colors.white, size: 28),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: (_bannerLoaded && _bannerAd != null)
          ? SafeArea(
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _uiTimer?.cancel();
    _blinkTimer?.cancel();
    _blinkAnimController.dispose();
    _bannerAd?.dispose();
    _persistStats();
    super.dispose();
  }
}

class _CountdownDialog extends StatefulWidget {
  final int seconds;
  final String title;
  final VoidCallback onFinished;

  const _CountdownDialog({
    required this.seconds,
    required this.title,
    required this.onFinished,
  });

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        widget.onFinished();
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text('$_secondsLeft', style: const TextStyle(fontSize: 48, color: Colors.blue)),
          const SizedBox(height: 10),
          const Text('ثانیه باقی‌مانده'),
        ],
      ),
    );
  }
}
