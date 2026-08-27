import 'package:flutter/services.dart';

/// پل ارتباطی با ScreenTimeService.kt (سرویس Foreground بومی اندروید).
/// روی هر پلتفرمی که این کانال پیاده نشده باشد (فعلاً iOS)، تمام متدها
/// به‌آرامی null/false برمی‌گردانند تا main.dart بتواند fallback کند —
/// بدون کرش و بدون وانمود کردن به این‌که قابلیت وجود دارد.
class NativeScreenTimeService {
  static const MethodChannel _channel =
      MethodChannel('com.eyecare.app/screen_time');

  /// مجموع ثانیه‌های واقعی روشن‌بودن صفحه امروز (مستقل از این‌که کدام
  /// اپ باز است). null یعنی پلتفرم پشتیبانی نمی‌شود.
  static Future<int?> getRealScreenTimeSeconds() async {
    try {
      final int seconds =
          await _channel.invokeMethod('getRealScreenTimeSeconds');
      return seconds;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> resetScreenTime() async {
    try {
      final bool success = await _channel.invokeMethod('resetScreenTime');
      return success;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// به سرویس بومی می‌گوید که اپ الان در foreground است یا نه؛ سرویس
  /// فقط وقتی اپ در پس‌زمینه است نوتیفیکیشن استراحت می‌فرستد، تا با
  /// دیالوگ‌های داخل‌اپ تداخل/تکرار نداشته باشد.
  static Future<void> setAppForeground(bool foreground) async {
    try {
      await _channel
          .invokeMethod('setAppForeground', {'foreground': foreground});
    } on PlatformException {
      // بی‌اثر روی پلتفرم‌هایی که این کانال را ندارند
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// فاصله‌ی استراحت کوتاه/طولانی (دقیقه) را به سرویس بومی می‌فرستد تا
  /// بعد از فرستادن هر نوتیفیکیشن پس‌زمینه، خودش بتواند آستانه‌ی بعدی
  /// را محاسبه کند.
  static Future<void> setBreakSettings({
    required int shortIntervalMinutes,
    required int longIntervalMinutes,
  }) async {
    try {
      await _channel.invokeMethod('setBreakSettings', {
        'shortIntervalMinutes': shortIntervalMinutes,
        'longIntervalMinutes': longIntervalMinutes,
      });
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// هر بار که Flutter آستانه‌ی «بعدی استراحت» را عوض می‌کند (مثلاً با
  /// دکمه‌ی تعویق)، این مقدار را به سرویس بومی هم می‌فرستد تا هر دو طرف
  /// همگام بمانند.
  static Future<void> setNextBreakThresholds({
    required int nextShortAtSeconds,
    required int nextLongAtSeconds,
  }) async {
    try {
      await _channel.invokeMethod('setNextBreakThresholds', {
        'nextShortAtSeconds': nextShortAtSeconds,
        'nextLongAtSeconds': nextLongAtSeconds,
      });
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// وقتی اپ از پس‌زمینه برمی‌گردد، این را صدا بزن تا اگر سرویس بومی در
  /// غیاب اپ یک نوتیفیکیشن فرستاده و آستانه را جلو برده، Flutter هم با
  /// همان مقدار جدید همگام شود (وگرنه بلافاصله یک دیالوگ تکراری نشان
  /// می‌دهد).
  static Future<Map<String, int>?> getNextBreakThresholds() async {
    try {
      final dynamic result =
          await _channel.invokeMethod('getNextBreakThresholds');
      final map = Map<Object?, Object?>.from(result as Map);
      return {
        'nextShortAtSeconds': map['nextShortAtSeconds'] as int,
        'nextLongAtSeconds': map['nextLongAtSeconds'] as int,
      };
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// روشن/خاموش‌کردن کامل مانیتورینگ در سمت سرویس بومی؛ وقتی خاموش است،
  /// سرویس هیچ نوتیفیکیشن استراحتی در پس‌زمینه نمی‌فرستد.
  static Future<void> setMonitoringEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setMonitoringEnabled', {'enabled': enabled});
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// توقف کامل سرویس پس‌زمینه (نه فقط خاموش‌کردن هشدارها) — نوتیفیکیشن
  /// دائمی هم حذف می‌شود و واقعاً هیچ چیزی از این اپ در پس‌زمینه نمی‌ماند.
  static Future<void> stopMonitoringService() async {
    try {
      await _channel.invokeMethod('stopMonitoringService');
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// راه‌اندازی دوباره‌ی سرویس پس‌زمینه بعد از این‌که کاربر مانیتورینگ
  /// را دوباره روشن کرد.
  static Future<void> startMonitoringService() async {
    try {
      await _channel.invokeMethod('startMonitoringService');
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// یک نوتیفیکیشن واقعی سیستم برای اعلام پایان شمارش معکوس ۲۰ ثانیه‌ای؛
  /// برخلاف SnackBar داخل‌اپ، حتی اگر صفحه قفل شود یا کاربر لحظه‌ای از
  /// اپ خارج شود هم دیده می‌شود.
  static Future<void> showBreakFinishedNotification() async {
    try {
      await _channel.invokeMethod('showBreakFinishedNotification');
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// فاصله‌ی یادآوری پلک (دقیقه) و فعال/غیرفعال بودنش را به سرویس بومی
  /// می‌فرستد تا خودش هم بتواند در پس‌زمینه (روی سایر اپ‌ها) یادآوری کند.
  static Future<void> setBlinkSettings({
    required int intervalMinutes,
    required bool enabled,
  }) async {
    try {
      await _channel.invokeMethod('setBlinkSettings', {
        'intervalMinutes': intervalMinutes,
        'enabled': enabled,
      });
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }

  /// آیا مجوز «نمایش روی اپ‌های دیگر» داده شده؟ بدون این مجوز، یادآوری‌های
  /// پس‌زمینه فقط با نوتیفیکیشن معمولی fallback می‌کنند (نه overlay واقعی).
  static Future<bool> checkOverlayPermission() async {
    try {
      final bool granted = await _channel.invokeMethod('checkOverlayPermission');
      return granted;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// کاربر را به صفحه‌ی تنظیمات اندروید برای دادن مجوز overlay می‌برد.
  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException {
    } on MissingPluginException {
      // بی‌اثر
    }
  }
}
