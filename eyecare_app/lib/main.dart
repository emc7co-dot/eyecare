import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'native_screen_time_service.dart';

void main() {
  runApp(const EyeCareApp());
}

class EyeCareApp extends StatelessWidget {
  const EyeCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'همراه سلامت چشم',
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

  EyeCareSettings({
    this.blinkReminderEnabled = true,
    this.blinkIntervalMinutes = 5,
    this.shortBreakIntervalMinutes = 20,
    this.longBreakIntervalMinutes = 120,
    this.strictLockMode = false,
  });

  factory EyeCareSettings.fromPrefs(SharedPreferences p) => EyeCareSettings(
        blinkReminderEnabled: p.getBool('blinkReminderEnabled') ?? true,
        blinkIntervalMinutes: p.getInt('blinkIntervalMinutes') ?? 5,
        shortBreakIntervalMinutes: p.getInt('shortBreakIntervalMinutes') ?? 20,
        longBreakIntervalMinutes: p.getInt('longBreakIntervalMinutes') ?? 120,
        strictLockMode: p.getBool('strictLockMode') ?? false,
      );

  Future<void> saveToPrefs(SharedPreferences p) async {
    await p.setBool('blinkReminderEnabled', blinkReminderEnabled);
    await p.setInt('blinkIntervalMinutes', blinkIntervalMinutes);
    await p.setInt('shortBreakIntervalMinutes', shortBreakIntervalMinutes);
    await p.setInt('longBreakIntervalMinutes', longBreakIntervalMinutes);
    await p.setBool('strictLockMode', strictLockMode);
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
  int _lastKnownTotalSeconds = 0;
  int _nextShortBreakAt = 0;
  int _nextLongBreakAt = 0;
  int _nextDistanceCheckAt = 0;
  static const int _distanceCheckIntervalSeconds = 45 * 60;

  Timer? _pollTimer;
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
    _stats = EyeCareStats.fromPrefs(prefs);

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
      await NativeScreenTimeService.setAppForeground(true);
      await _syncThresholdsToNative();
    }

    if (!mounted) return;
    setState(() => _loaded = true);
    _startTicking();
    _restartBlinkTimer();
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
    final interval =
        _nativeAvailable ? const Duration(seconds: 5) : const Duration(seconds: 1);
    _pollTimer = Timer.periodic(interval, (_) => _tick());
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
    if (!_settings.blinkReminderEnabled) return;
    _blinkTimer = Timer.periodic(
      Duration(minutes: _settings.blinkIntervalMinutes),
      (_) {
        if (_appInForeground && !_dialogOpen) {
          _triggerBlinkAnimation();
        }
      },
    );
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
    final nativeThresholds = await NativeScreenTimeService.getNextBreakThresholds();
    if (nativeThresholds != null) {
      _nextShortBreakAt = nativeThresholds['nextShortAtSeconds']!;
      _nextLongBreakAt = nativeThresholds['nextLongAtSeconds']!;
    }
    if (mounted) _tick();
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
                title: const Text('یادآوری دیداری پلک زدن'),
                subtitle: const Text('انیمیشن بسیار کوتاه، بدون صدا و ویبره'),
                value: _settings.blinkReminderEnabled,
                onChanged: (v) {
                  setSheetState(() => _settings.blinkReminderEnabled = v);
                  setState(() {});
                  _persistSettings();
                  _restartBlinkTimer();
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
            Text('همراه سلامت چشم',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 12),
            Text('سازنده: احسان ایزدی'),
            SizedBox(height: 4),
            Text('وب‌سایت: Wining.ir'),
            SizedBox(height: 4),
            Text('ایمیل: ehsanizadiasl@gmail.com'),
            SizedBox(height: 4),
            Text('اینستاگرام: @Makarechian_7'),
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
        title: const Text('همراه سلامت چشم'),
        actions: [
          IconButton(icon: const Icon(Icons.bar_chart), onPressed: _showDailyReport),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showAboutDialog),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettingsSheet),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('زمان فعال صفحه امروز'),
                      const SizedBox(height: 8),
                      Text(
                        '${_stats.screenTimeSeconds ~/ 3600}:'
                        '${((_stats.screenTimeSeconds % 3600) ~/ 60).toString().padLeft(2, '0')}:'
                        '${(_stats.screenTimeSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _nativeAvailable
                            ? 'منبع: زمان واقعی صفحه (بومی، شامل سایر اپ‌ها)'
                            : 'منبع: تخمین محلی (فقط زمان همین اپ)',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.remove_red_eye),
                title: const Text('تست انیمیشن پلک زدن'),
                onTap: _triggerBlinkAnimation,
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('تست یادآوری استراحت کوتاه (۲۰-۲۰-۲۰)'),
                onTap: _triggerShortBreakDialog,
              ),
            ],
          ),
          if (_showBlinkOverlay)
            Positioned(
              top: 40,
              right: 20,
              child: AnimatedBuilder(
                animation: _blinkAnimController,
                builder: (context, child) {
                  return Transform.scale(
                    scaleY: 1.0 - (_blinkAnimController.value * 0.9),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child:
                          const Icon(Icons.remove_red_eye, color: Colors.white, size: 28),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _blinkTimer?.cancel();
    _blinkAnimController.dispose();
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
