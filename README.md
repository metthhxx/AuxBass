# AuxBass (Android) 🎵

> Нативный Android-клиент для музыкального сервиса [aux.ganj4craft.ru](https://aux.ganj4craft.ru).

[![GitHub Release](https://img.shields.io/github/v/release/metthhxx/AuxBass?color=1ED760&style=flat-square)](https://github.com/metthhxx/AuxBass/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Android%208.0%2B-brightgreen?style=flat-square)](https://github.com/metthhxx/AuxBass)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?style=flat-square)](https://flutter.dev)

---

## ✨ Возможности

- 🚀 **144 Гц и ультраплавность:** Аппаратный рендеринг на Flutter Impeller Vulkan с разблокированной частотой обновления дисплея (включая флагманские 120/144 Гц экраны).
- 🎨 **Material You 3 Дизайн:** Тёмная эстетика AuxBass с динамическими тонами, кастомными шрифтами Minecraft и фирменным стилем.
- 🎛 **Управление жестами:**
  - Свайп влево / вправо по мини-плееру и полноэкранному плееру для переключения треков.
  - Плавное разворачивание плеера прямо из мини-виджета.
  - Свайп вниз для сворачивания плеера.
- 🔔 **Плеер в шторке уведомлений:**
  - Полноценное управление музыкой (Play/Pause, Next, Previous, Seek).
  - Отображение обложек треков и метаданных в системной шторке Android (Android MediaStyle / AudioService).
- 🔄 **OTA-обновления (Over-The-Air):**
  - Автоматическая проверка обновлений при запуске и через меню профиля.
  - Прямое скачивание свежих APK из GitHub Releases с индикатором прогресса и бесшовным запуском системного установщика.
- 👥 **Подписки и Авторы:**
  - Каталог исполнителей с сайта.
  - Быстрый переход в профили музыкантов и прослушивание их дискографии.
- 🔍 **Поиск и Библиотека:**
  - Раздельный поиск: по локальным трекам и по всей базе сайта.
  - Подкатегории плейлистов и любимых треков.
  - Шафл по всей онлайн-базе сайта.
- ☁️ **Интеграция с SoundCloud:**
  - Синхронизация треков и плейлистов напрямую через профиль.

---

## 📥 Установка

1. Перейдите на страницу [GitHub Releases](https://github.com/metthhxx/AuxBass/releases/latest).
2. Скачайте файл **`AuxBass.apk`**.
3. Установите на ваше Android-устройство (разрешите установку из неизвестных источников, если потребуется).
4. Все последующие обновления будут приходить автоматически прямо внутри приложения!

---

## 🛠 Разработка и сборка

### Требования
- Flutter SDK 3.24+
- Android SDK (API 34/35/36, NDK)
- Java 17+

### Сборка Release APK
```bash
# Получение зависимостей
flutter pub get

# Сборка оптимизированного APK
flutter build apk --release
```
Готовый файл появится по пути: `build/app/outputs/flutter-apk/app-release.apk`.

---

## 📄 Лицензия
AuxBass Player разработан для сообщества [ganj4craft.ru](https://aux.ganj4craft.ru).
