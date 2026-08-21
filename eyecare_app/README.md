# همراه سلامت چشم — راهنمای ساخت

## این پروژه چیست؟
یک اپ فلاتر (Flutter) برای اندروید که یادآوری پلک زدن، استراحت کوتاه (۲۰-۲۰-۲۰)،
بررسی فاصله از صفحه و استراحت طولانی را با استفاده از یک Foreground Service
بومی اندروید پیاده می‌کند.

## ساختار فایل‌ها
```
eyecare_app/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   └── native_screen_time_service.dart
└── android/
    └── app/
        └── src/
            └── main/
                ├── AndroidManifest.xml
                └── kotlin/
                    └── com/example/eyecare/
                        ├── MainActivity.kt
                        └── ScreenTimeService.kt
```

## نحوه استفاده (روش ابری / بدون نصب Flutter روی سیستم)

1. یک Repository جدید در GitHub بساز.
2. تمام فایل‌ها و پوشه‌های داخل این فولدر (eyecare_app) را — با حفظ دقیق
   ساختار پوشه‌ها — در ریشه‌ی Repository آپلود کن (Add file → Upload files
   در گیت‌هاب، یا drag & drop پوشه‌ها).
3. یک اکانت در codemagic.io بساز و همان Repository را وصل کن.
4. Codemagic به‌طور خودکار پروژه‌ی Flutter را تشخیص می‌دهد؛ روی Start Build بزن.
5. بعد از اتمام بیلد، فایل APK قابل دانلود است.

## نحوه استفاده (نصب محلی Flutter روی لپ‌تاپ)

```
flutter create --org com.example eyecare_app_new
```
سپس فایل‌های این پوشه را جایگزین فایل‌های مشابه در پروژه‌ی تازه‌ساخته‌شده کن،
و اجرا کن:
```
flutter pub get
flutter run
```

## نکات مهم قبل از انتشار
- `com.example.eyecare` را با applicationId واقعی پروژه‌ات یکسان کن (در
  AndroidManifest.xml و هر دو فایل Kotlin، خط package).
- آیکون نوتیفیکیشن پیش‌فرض سیستمی است؛ برای انتشار نهایی بهتر است آیکون
  اختصاصی طراحی شود.
- در iOS این نسخه پیاده‌سازی بومی ندارد و به‌صورت خودکار به تخمین محلی
  foreground-only برمی‌گردد.
