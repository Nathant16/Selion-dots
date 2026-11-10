# Руководство по архитектуре и изменениям Selion (Selion Fork Guide)

> **Назначение документа**: Этот файл содержит полное описание всех доработок, архитектурных решений, отличий от оригинального Serpantinum и инвариантов Selion.
> **Для ИИ-ассистента и разработчика**: При каждом обновлении апстрима (`upstream/master`) или внесении новых функций сверяйтесь с этим чеклистом, чтобы гарантировать целостность райза.

---

## 1. Репозитории и ветки

- **Upstream (Оригинал)**: `https://github.com/ilyamiro/Serpantinum.git` (remote: `upstream`)
- **Origin (Selion)**: `git@github.com:Nathant16/Selion-dots.git` (remote: `origin`)
- **Ветка `master`**: Основной исходный код райза Selion, конфиги, скрипты и QML-интерфейс.
- **Ветка `wallpapers`**: Автономная ветка без истории родительских коммитов (orphan/isolated branch), содержащая коллекцию 130 обоев высокого качества (UHD/QHD/FHD, ~508 МБ). Это сделано для того, чтобы не раздувать историю коммитов `master` тяжелыми бинарными файлами.

---

## 2. Полный реестр изменений Selion (Отличия от Serpantinum)

### 2.1. Ребрендинг и метаданные
- **Авторство и брендинг**: Serpantinum переименован в Selion (`@Nathant`).
- **Ссылки на проект**: Заменены на `https://github.com/Nathant16/Selion-dots` и Telegram `https://t.me/Nathant16`.
- **Файлы ребрендинга**:
  - `src/quickshell/guide/AboutTab.qml`: Карточка проекта, имя, ссылки, баннер.
  - `src/quickshell/guide/WelcomeTab.qml`: Расчёт длины заголовка сделан динамическим (`Math.max(1, title.length - "Selion".length)`), чтобы заголовок не обрезался на длинных строках локализации.
  - `src/quickshell/guide/theme/ThemePresetsSection.qml`: Удалены привязки к соцсетям оригинального автора.
  - `install/modules/ui.sh`: ASCII-логотип SELION при установке.

### 2.2. Система обоев (Wallpapers Architecture)
1. **Локация обоев**:
   - Обои Selion устанавливаются в подпапку: `~/Pictures/Wallpapers/Selion/`.
   - Пользовательские обои могут лежать в `~/Pictures/Wallpapers/` или в любых других вложенных папках (`~/Pictures/Wallpapers/Anime/`, `~/Pictures/Wallpapers/Nature/` и т.д.).
2. **Безопасная очистка старых обоев (Legacy Cleanup)**:
   - В `install/modules/deploy.sh` функция `install_wallpapers()` клонирует/синхронизирует ветку `wallpapers` только в `~/Pictures/Wallpapers/Selion/`.
   - При обновлении скрипт находит и безопасно удаляет старые файлы обоев Serpantinum (`1.png`..`17.png` из оригинального репозитория `ilyamiro/shell-wallpapers`) из корня `~/Pictures/Wallpapers/`, не затрагивая пользовательские изображения.
   - Фиксируется маркер `~/.local/state/serpantinum/legacy_wallpapers_cleaned`.
3. **Рекурсивное индексирование обоев**:
   - Скрипт `src/scripts/wallpaper/recursive_index.py`: рекурсивно обходит директорию `~/Pictures/Wallpapers` со всеми подпапками, обёртывая `serpantinum-core wallpaper index` для каждой папки и формируя относительные пути вида `Selion/1.png`, `Folder/pic.jpg`.
   - Возвращает единый JSON с относительными путями `fileName`, полными `filePath`, `fileUrl` и временной меткой `mtime` (для вкладки недавно добавленных).
4. **Параметр «Отображать обои Selion» (`showSelionWallpapers`)**:
   - Добавлен ключ `"showSelionWallpapers": true` в `config/serpantinum/settings.json`.
   - Компонент `ShowSelionRow.qml` в `src/quickshell/guide/wallpaper/`, зарегистрирован в `qmldir`.
   - Интегрирован в `WallpaperTab.qml` и `WallpaperTabState.qml`.
   - При отключении опции обои из папки `Selion/` мгновенно скрываются из выбора в `WallpaperPicker.qml` и исключаются из случайного перемешивания в `Wallpaper.qml`.
5. **Скрипты первого запуска и генерации миниатюр**:
   - `src/scripts/qs_manager.sh`: генерация превью теперь рекурсивная (`find -type f` с поддержкой поддиректорий) и учитывает флаг `showSelionWallpapers`.
   - `src/scripts/first_launch.sh`: случайный выбор первых обоев рекурсивно ищет файлы во всех подпапках, отдавая предпочтение `Selion/1.png` при первом старте.

### 2.3. Аппаратные фиксы и интеграция
1. **Профили энергопотребления (Power Profiles)**:
   - Двусторонняя реактивная синхронизация выбранного профиля питания между боковой панелью (`SystemPanel.qml`) и настройками (`PowerTab.qml`).
   - Плавное угасание яркости (5 секунд).
   - Адаптивный селектор частоты процессора под текущее железо.
2. **Определение дисплеев (Display Detection)**:
   - `src/quickshell/guide/display/DisplayMainState.qml`: добавлена функция `loadFallbackScreens()`. Если детектор мониторов возвращает пустой список или работает под нестандартным Wayland-композитором, настройки не падают с пустым экраном, а считывают свойства экранов напрямую из `Quickshell.screens`.
3. **Сканер отпечатков пальцев (Polkit & Fingerprint)**:
   - В диалоге аутентификации Polkit добавлено визуальное ожидание сканирования пальца, когда задействован PAM-модуль `fprintd`.

### 2.4. Локализация (23 языка)
- **Канонический эталон**: `src/assets/languages/en.json`.
- **Все 23 локали**: `ar, az, bg, de, en, es, fa, fr, hi, hy, id, it, ja, ko, nl, pl, pt, ru, tr, ua, vi, zh, zh_tw`.
- **Правила строгого паритета**:
  - В каждом языковом файле содержится **ровно 100% совпадающий набор ключей** в идентичном иерархическом порядке.
  - Удалены устаревшие неиспользуемые ключи (dead keys): `guide.autostart.*`, `guide.weather.quiet.*`, `widgets.presets.*.desc`.
  - Все новые ключи Selion (`guide.theme.wallpaper.show_selion.*`) и добавленные ключи апстрима (`guide.display.lockscreen.prompt_backdrop.*`) полноценно переведены на все языки без английских заглушек.

---

## 3. Инструкция: Как интегрировать обновления оригинального Serpantinum

При выходе новых коммитов в оригинале `ilyamiro/Serpantinum`:

### Шаг 1. Получение изменений
```bash
git fetch upstream
git log --oneline master..upstream/master
```

### Шаг 2. Слияние
```bash
git merge upstream/master
```

### Шаг 3. Разрешение типичных конфликтов
1. **`packaging/aur/*`**:
   Если апстрим обновил файлы в `packaging/aur/` (которые удалены в Selion), удалите их:
   ```bash
   git rm -f packaging/aur/serpantinum/PKGBUILD packaging/aur/serpantinum-git/PKGBUILD
   ```
2. **`src/quickshell/guide/wallpaper/WallpaperTab.qml`**:
   Убедитесь, что `ShowSelionRow` остаётся включённым сразу под `WallpaperDirRow`:
   ```qml
   WallpaperDirRow { id: wallpaperDirRow; tab: wallpaperTabRoot }

   ShowSelionRow { tab: wallpaperTabRoot }

   Loader {
       Layout.fillWidth: true
       active: wallpaperTabRoot.deferredStage >= 1
       sourceComponent: TransitionModeRow { tab: wallpaperTabRoot }
   }
   ```
3. **`src/quickshell/guide/display/DisplayMainState.qml`**:
   Сохраняйте вызов `loadFallbackScreens()` как fallback при пустом списке мониторов.
4. **`src/assets/languages/*.json`**:
   Если апстрим добавил новые ключи (например, в `en.json`), запустите валидатор ключей (см. раздел 4). Убедитесь, что новые ключи добавлены во все 23 файла.

---

## 4. Чеклист проверки целостности райза (Прогонять перед каждым релизом!)

Выполните следующие тесты в терминале:

```bash
# 1. Проверка синтаксиса всех Bash-скриптов
find . -name "*.sh" -exec bash -n {} +

# 2. Проверка синтаксиса всех Python-скриптов
find . -name "*.py" -exec python3 -m py_compile {} +

# 3. Проверка паритета всех 23 файлов локализации
python3 -c '
import json, glob
en = json.load(open("src/assets/languages/en.json"))
def get_k(d, p=""):
    k = set()
    for key, val in d.items():
        np = f"{p}.{key}" if p else key
        if isinstance(val, dict): k.update(get_k(val, np))
        else: k.add(np)
    return k
ek = get_k(en)
errs = []
for f in sorted(glob.glob("src/assets/languages/*.json")):
    k = get_k(json.load(open(f)))
    if ek != k:
        errs.append(f"{f}: missing {len(ek-k)}, extra {len(k-ek)}")
if errs:
    print("ОШИБКИ ЛОКАЛИЗАЦИИ:\n" + "\n".join(errs))
    exit(1)
else:
    print(f"Все 23 языка идентичны! Всего ключей: {len(ek)}")
'

# 4. Проверка QML-компонентов Selion
qmllint src/quickshell/guide/wallpaper/ShowSelionRow.qml src/quickshell/guide/wallpaper/WallpaperTabState.qml
```

Если все 4 шага прошли без ошибок — райз полностью стабилен и готов к сборке/релизу.
