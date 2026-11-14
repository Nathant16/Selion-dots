#!/usr/bin/env python3
import os
import sys
import json
import re
import subprocess
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
SETTINGS_PATH = CONFIG_DIR / "serpantinum" / "settings.json"

def get_active_compositor():
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    if os.environ.get("DRIFTWM_SOCKET") or "drift" in desktop:
        return "driftwm"
    if os.environ.get("NIRI_SOCKET") or "niri" in desktop:
        return "niri"
    if os.environ.get("MANGO_INSTANCE_SIGNATURE") or "mango" in desktop:
        return "mango"
    if os.environ.get("SWAYSOCK") or "sway" in desktop:
        return "sway"
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") or "hyprland" in desktop:
        return "hyprland"
    
    # Check running processes
    try:
        ps = subprocess.check_output(["ps", "-u", str(os.getuid()), "-o", "comm="], text=True)
        for wm in ["hyprland", "sway", "niri", "mango", "driftwm"]:
            if wm in ps:
                return wm
    except Exception:
        pass
    return "hyprland"

def get_standard_keybindings(compositor):
    # Common core keybindings present across all 5 WMs
    base = [
        # --- Shell & System ---
        {"id": "kb_settings", "cat": "shell", "keys": ["Super", "I"], "title": "Настройки системы", "desc": "Открыть или скрыть панель настроек и руководства Serpantinum"},
        {"id": "kb_launcher", "cat": "shell", "keys": ["Super", "A"], "title": "Меню приложений", "desc": "Открыть всплывающий лаунчер поиска и запуска программ"},
        {"id": "kb_clipboard", "cat": "shell", "keys": ["Super", "V"], "title": "Буфер обмена", "desc": "Менеджер истории скопированного текста и картинок"},
        {"id": "kb_wallpaper", "cat": "shell", "keys": ["Super", "W"], "title": "Выбор обоев", "desc": "Галерея для быстрой смены фона рабочего стола"},
        {"id": "kb_bar", "cat": "shell", "keys": ["Super", "B"], "title": "Скрыть / показать бар", "desc": "Переключить автоскрытие верхней панели"},
        {"id": "kb_lock", "cat": "shell", "keys": ["Super", "L"], "title": "Блокировка экрана", "desc": "Заблокировать сессию с экраном блокировки Serpantinum"},
        {"id": "kb_reload", "cat": "shell", "keys": ["Super", "R"], "title": "Перезагрузить оболочку", "desc": "Мягкий перезапуск интерфейса Quickshell"},
        {"id": "kb_btop", "cat": "shell", "keys": ["Ctrl", "Shift", "Esc"], "title": "Диспетчер процессов", "desc": "Запустить терминальный монитор ресурсов btop"},
        {"id": "kb_layout", "cat": "shell", "keys": ["Alt", "Shift"], "title": "Смена раскладки", "desc": "Переключение языка ввода (US / RU) (также Ctrl+Shift)"},

        # --- Window Management ---
        {"id": "kb_term", "cat": "windows", "keys": ["Super", "Enter"], "title": "Терминал", "desc": "Запустить эмулятор терминала Kitty"},
        {"id": "kb_close", "cat": "windows", "keys": ["Super", "Q"], "title": "Закрыть окно", "desc": "Закрыть текущее активное приложение"},
        {"id": "kb_fullscreen", "cat": "windows", "keys": ["Alt", "Enter"], "title": "Полноэкранный режим", "desc": "Развернуть окно на весь экран"},
        {"id": "kb_floating", "cat": "windows", "keys": ["Super", "Space"], "title": "Плавающий режим / Закрепление", "desc": "Открепить окно или зафиксировать поверх всех"},
        {"id": "kb_center", "cat": "windows", "keys": ["Super", "Backspace"], "title": "Центрировать / Скретчпад", "desc": "Выровнять окно по центру или вызвать скретчпад"},
        {"id": "kb_cycle_next", "cat": "windows", "keys": ["Alt", "Tab"], "title": "Следующее окно", "desc": "Быстрое переключение между открытыми окнами"},
        {"id": "kb_cycle_prev", "cat": "windows", "keys": ["Alt", "Shift", "Tab"], "title": "Предыдущее окно", "desc": "Переключение на предыдущее окно"},
        {"id": "kb_focus_arrows", "cat": "windows", "keys": ["Super", "Стрелки"], "title": "Фокус окна", "desc": "Переместить фокус на соседнее окно (влево / вправо / вверх / вниз)"},
        {"id": "kb_move_snap", "cat": "windows", "keys": ["Super", "Alt", "Стрелки"], "title": "Перемещение окна", "desc": "Привязать или передвинуть окно в направлении стрелки"},
        {"id": "kb_resize_arrows", "cat": "windows", "keys": ["Super", "Shift", "Стрелки"], "title": "Изменение размера", "desc": "Увеличить или уменьшить габариты активного окна"},
        {"id": "kb_ws_switch", "cat": "windows", "keys": ["Super", "1..9"], "title": "Переход на стол / закладку", "desc": "Переключиться на рабочий стол или закладку с номером 1-9"},
        {"id": "kb_ws_move", "cat": "windows", "keys": ["Super", "Shift", "1..9"], "title": "Окно на стол / закладку", "desc": "Перенести текущее окно на указанный рабочий стол"},

        # --- Applications ---
        {"id": "kb_fm", "cat": "apps", "keys": ["Super", "E"], "title": "Файловый менеджер", "desc": "Открыть быстрый проводник файлов Ski"},
        {"id": "kb_zen", "cat": "apps", "keys": ["Super", "Shift", "Z"], "title": "Браузер Zen", "desc": "Запустить веб-браузер Zen Browser"},
        {"id": "kb_code", "cat": "apps", "keys": ["Super", "Shift", "C"], "title": "Visual Studio Code", "desc": "Открыть редактор исходного кода VS Code"},
        {"id": "kb_spotify", "cat": "apps", "keys": ["Super", "Shift", "S"], "title": "Музыка Spotify", "desc": "Запустить плеер Spotify"},
        {"id": "kb_telegram", "cat": "apps", "keys": ["Super", "Shift", "T"], "title": "Telegram / AyuGram", "desc": "Открыть мессенджер Telegram"},
        {"id": "kb_discord", "cat": "apps", "keys": ["Super", "Shift", "D"], "title": "Discord", "desc": "Запустить Discord для общения"},
        {"id": "kb_steam", "cat": "apps", "keys": ["Super", "Shift", "G"], "title": "Игры Steam", "desc": "Запустить игровую платформу Steam"},
        {"id": "kb_obsidian", "cat": "apps", "keys": ["Super", "Shift", "O"], "title": "Заметки Obsidian", "desc": "Открыть базу знаний и заметок Obsidian"},

        # --- Screenshots & Media ---
        {"id": "kb_shot_area", "cat": "media", "keys": ["Print"], "title": "Скриншот области", "desc": "Выделить область экрана и скопировать снимок в буфер"},
        {"id": "kb_shot_edit", "cat": "media", "keys": ["Shift", "Print"], "title": "Снимок с аннотациями", "desc": "Выделить область и сразу открыть в редакторе Satty"},
        {"id": "kb_shot_full", "cat": "media", "keys": ["Super", "Print"], "title": "Полный скриншот", "desc": "Снимок всего экрана целиком"},
        {"id": "kb_shot_full_edit", "cat": "media", "keys": ["Super", "Shift", "Print"], "title": "Полный снимок с редактором", "desc": "Снимок всего экрана и открытие в Satty"},
        {"id": "kb_vol_up_down", "cat": "media", "keys": ["Fn", "Громкость"], "title": "Регулировка звука", "desc": "Увеличить / уменьшить громкость с OSD-индикацией"},
        {"id": "kb_vol_mute", "cat": "media", "keys": ["Fn", "Mute"], "title": "Отключить звук", "desc": "Быстро заглушить звук или микрофон"},
        {"id": "kb_bright", "cat": "media", "keys": ["Fn", "Яркость"], "title": "Яркость экрана", "desc": "Регулировка подсветки дисплея с OSD-индикацией"},
        {"id": "kb_player", "cat": "media", "keys": ["Fn", "Плеер"], "title": "Управление медиа", "desc": "Воспроизведение, пауза, следующий и предыдущий трек"}
    ]

    # Compositor-specific extras
    if compositor == "driftwm":
        base.append({"id": "kb_drift_zoom_in", "cat": "windows", "keys": ["Super", "+"], "title": "Приблизить холст", "desc": "Увеличить масштаб бесконечного холста DriftWM"})
        base.append({"id": "kb_drift_zoom_out", "cat": "windows", "keys": ["Super", "-"], "title": "Отдалить холст", "desc": "Уменьшить масштаб холста DriftWM"})
        base.append({"id": "kb_drift_zoom_reset", "cat": "windows", "keys": ["Super", "0"], "title": "Сбросить зум", "desc": "Вернуть 100% масштаб холста DriftWM"})
    elif compositor == "niri":
        base.append({"id": "kb_niri_col_left", "cat": "windows", "keys": ["Super", "H"], "title": "Колонка влево", "desc": "Фокус на колонку слева в ленте Niri"})
        base.append({"id": "kb_niri_col_right", "cat": "windows", "keys": ["Super", "L"], "title": "Колонка вправо", "desc": "Фокус на колонку справа в ленте Niri"})

    return base

def load_settings():
    if not SETTINGS_PATH.exists():
        return {}
    try:
        with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def save_settings(data):
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

def get_custom_bindings():
    s = load_settings()
    return s.get("custom_keybindings", [])

def update_block_in_text(existing_content, new_block_lines, comment_char="#", default_header=""):
    begin_marker = f"{comment_char} BEGIN SERPANTINUM KEYBINDINGS"
    end_marker = f"{comment_char} END SERPANTINUM KEYBINDINGS"

    if begin_marker in existing_content and end_marker in existing_content:
        before = existing_content.split(begin_marker)[0]
        after = existing_content.split(end_marker)[1]
        base = before.rstrip() + "\n" + after.lstrip()
    elif "Autogenerated userprefs" in existing_content:
        base = default_header.strip() if default_header else ""
    else:
        base = existing_content.strip()
        if not base and default_header:
            base = default_header.strip()

    block_str = f"{begin_marker}\n" + "\n".join(new_block_lines) + f"\n{end_marker}"
    if base:
        return base.rstrip() + "\n\n" + block_str + "\n"
    return block_str + "\n"

def sync_userprefs(compositor):
    bindings = get_custom_bindings()
    home = Path.home()

    if compositor == "hyprland":
        target = home / ".config" / "hypr" / "userprefs.lua"
        lines = []
        for b in bindings:
            if not b.get("enabled", True):
                continue
            key = b.get("key", "").strip()
            cmd = b.get("exec", "").strip().replace('"', '\\"')
            if key and cmd:
                lines.append(f'hl.bind("{key}", hl.dsp.exec_cmd("{cmd}"))')

        existing = ""
        if target.exists():
            try: existing = target.read_text(encoding="utf-8")
            except Exception: pass

        updated = update_block_in_text(existing, lines, comment_char="--", default_header='pcall(require, "workflows/default")\n')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(updated, encoding="utf-8")
        subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    elif compositor == "sway":
        target = home / ".config" / "sway" / "userprefs"
        lines = []
        for b in bindings:
            if not b.get("enabled", True):
                continue
            raw_key = "".join(b.get("key", "").split())
            key = raw_key.replace("Super", "$mod").replace("super", "$mod")
            cmd = b.get("exec", "").strip()
            if key and cmd:
                lines.append(f"bindsym {key} exec {cmd}")

        existing = ""
        if target.exists():
            try: existing = target.read_text(encoding="utf-8")
            except Exception: pass

        updated = update_block_in_text(existing, lines, comment_char="#", default_header="include workflows/default\n")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(updated, encoding="utf-8")
        subprocess.run(["swaymsg", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    elif compositor == "niri":
        target = home / ".config" / "niri" / "userprefs.kdl"
        lines = ["binds {"]
        for b in bindings:
            if not b.get("enabled", True):
                continue
            raw_key = "".join(b.get("key", "").split())
            key = raw_key.replace("Super", "Mod").replace("super", "Mod")
            cmd = b.get("exec", "").strip().replace('"', '\\"')
            if key and cmd:
                lines.append(f'    {key} {{ spawn "sh" "-c" "{cmd}"; }}')
        lines.append("}")

        existing = ""
        if target.exists():
            try: existing = target.read_text(encoding="utf-8")
            except Exception: pass

        updated = update_block_in_text(existing, lines, comment_char="//", default_header='include optional=true "workflows/default.kdl"\n')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(updated, encoding="utf-8")
        subprocess.run(["niri", "msg", "action", "load-config-file"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    elif compositor == "mango":
        target = home / ".config" / "mango" / "userprefs.conf"
        lines = []
        for b in bindings:
            if not b.get("enabled", True):
                continue
            raw_parts = [p.strip() for p in b.get("key", "").split("+") if p.strip()]
            cmd = b.get("exec", "").strip()
            if not raw_parts or not cmd:
                continue
            if len(raw_parts) == 1:
                k = raw_parts[0]
                lines.append(f"bind={k},spawn,{cmd}")
            else:
                mods = "+".join(raw_parts[:-1]).upper()
                k = raw_parts[-1]
                lines.append(f"bind={mods},{k},spawn,{cmd}")

        existing = ""
        if target.exists():
            try: existing = target.read_text(encoding="utf-8")
            except Exception: pass

        updated = update_block_in_text(existing, lines, comment_char="#", default_header="source_optional=~/.config/mango/workflows/default.conf\n")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(updated, encoding="utf-8")
        subprocess.run(["mmsg", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    elif compositor == "driftwm":
        target = home / ".config" / "driftwm" / "config.toml"
        lines = []
        for b in bindings:
            if not b.get("enabled", True):
                continue
            raw_parts = [p.strip().lower() for p in b.get("key", "").split("+") if p.strip()]
            cmd = b.get("exec", "").strip()
            if not raw_parts or not cmd:
                continue
            parts = [("mod" if p in ("super", "mod4") else p) for p in raw_parts]
            drift_key = "+".join(parts)
            lines.append(f'"{drift_key}" = "spawn {cmd}"')

        if target.exists():
            try:
                cfg_text = target.read_text(encoding="utf-8")
                begin_marker = '# BEGIN SERPANTINUM KEYBINDINGS'
                end_marker = '# END SERPANTINUM KEYBINDINGS'
                if begin_marker in cfg_text and end_marker in cfg_text:
                    before = cfg_text.split(begin_marker)[0]
                    after = cfg_text.split(end_marker)[1]
                    base = before.rstrip() + "\n" + after.lstrip()
                else:
                    base = cfg_text
                block_str = f"{begin_marker}\n" + "\n".join(lines) + f"\n{end_marker}"
                header = "[keybindings]" if "[keybindings]" in base else ("[keybinds]" if "[keybinds]" in base else None)
                if header:
                    p1, p2 = base.split(header, 1)
                    updated = p1 + header + "\n" + block_str + "\n" + p2.lstrip("\n")
                else:
                    updated = base.rstrip() + "\n\n[keybindings]\n" + block_str + "\n"
                target.write_text(updated, encoding="utf-8")
            except Exception:
                pass
        subprocess.run(["driftwm", "msg", "action", "reload-config"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "list"
    comp = get_active_compositor()

    if action == "list":
        std = get_standard_keybindings(comp)
        custom = get_custom_bindings()
        out = {
            "compositor": comp,
            "standard": std,
            "custom": custom
        }
        print(json.dumps(out, ensure_ascii=False))

    elif action == "add":
        # Arguments: key, cmd, title/desc
        key = sys.argv[2] if len(sys.argv) > 2 else ""
        cmd = sys.argv[3] if len(sys.argv) > 3 else ""
        title = sys.argv[4] if len(sys.argv) > 4 else cmd
        if not key or not cmd:
            print(json.dumps({"error": "Key and command required"}))
            sys.exit(1)
        s = load_settings()
        custom = s.get("custom_keybindings", [])
        new_id = f"custom_{int(os.times().system * 1000)}_{len(custom)}"
        custom.append({
            "id": new_id,
            "key": key,
            "exec": cmd,
            "title": title,
            "desc": f"Запуск: {cmd}",
            "enabled": True
        })
        s["custom_keybindings"] = custom
        save_settings(s)
        sync_userprefs(comp)
        print(json.dumps({"success": True, "id": new_id}))

    elif action in ("delete", "remove"):
        target_id = sys.argv[2] if len(sys.argv) > 2 else ""
        s = load_settings()
        custom = s.get("custom_keybindings", [])
        custom = [b for b in custom if b.get("id") != target_id]
        s["custom_keybindings"] = custom
        save_settings(s)
        sync_userprefs(comp)
        print(json.dumps({"success": True}))

    elif action == "sync":
        sync_userprefs(comp)
        print(json.dumps({"success": True}))

if __name__ == "__main__":
    main()

