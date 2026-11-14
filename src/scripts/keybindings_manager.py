#!/usr/bin/env python3
import os
import sys
import json
import re
import subprocess
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
SETTINGS_PATH = CONFIG_DIR / "serpantinum" / "settings.json"

STANDARD_COMMANDS = {
    "kb_settings": "serpantinum settings",
    "kb_launcher": "serpantinum msg toggle launcher",
    "kb_clipboard": "serpantinum msg toggle clipboard",
    "kb_wallpaper": "serpantinum msg toggle wallpaper",
    "kb_bar": "serpantinum msg bar autohide",
    "kb_lock": "serpantinum lock",
    "kb_reload": "serpantinum reload",
    "kb_btop": "kitty -e btop",
    "kb_term": "kitty",
    "kb_close": "kill",
    "kb_fullscreen": "fullscreen",
    "kb_floating": "floating",
    "kb_center": "center",
    "kb_fm": "kitty -e ski",
    "kb_zen": "zen-browser",
    "kb_code": "code",
    "kb_spotify": "spotify",
    "kb_telegram": "AyuGram",
    "kb_discord": "discord",
    "kb_steam": "steam",
    "kb_obsidian": "obsidian",
    "kb_shot_area": "serpantinum screenshot",
    "kb_shot_edit": "serpantinum screenshot --edit",
    "kb_shot_full": "serpantinum screenshot --full",
    "kb_shot_full_edit": "serpantinum screenshot --full --edit",
    "kb_vol_up_down": "serpantinum volume lower",
    "kb_vol_mute": "serpantinum volume mute-toggle",
    "kb_bright": "serpantinum brightness lower",
    "kb_player": "playerctl play-pause",
    "kb_drift_zoom_in": "zoom-in",
    "kb_drift_zoom_out": "zoom-out",
    "kb_drift_zoom_reset": "zoom-reset",
    "kb_niri_col_left": "focus-column-left",
    "kb_niri_col_right": "focus-column-right"
}

# Original key mapping in DriftWM config.toml
DRIFT_DEFAULT_KEY_MAP = {
    "kb_settings": "mod+i",
    "kb_launcher": "mod+a",
    "kb_clipboard": "mod+v",
    "kb_wallpaper": "mod+w",
    "kb_bar": "mod+b",
    "kb_lock": "mod+l",
    "kb_reload": "mod+r",
    "kb_term": "mod+return",
    "kb_close": "mod+q",
    "kb_fullscreen": "alt+return",
    "kb_floating": "mod+space",
    "kb_center": "mod+backspace",
    "kb_fm": "mod+e",
    "kb_zen": "mod+shift+z",
    "kb_code": "mod+shift+c",
    "kb_spotify": "mod+shift+s",
    "kb_telegram": "mod+shift+t",
    "kb_discord": "mod+shift+d",
    "kb_steam": "mod+shift+g",
    "kb_obsidian": "mod+shift+o",
    "kb_shot_area": "Print",
    "kb_shot_edit": "shift+Print",
    "kb_shot_full": "mod+Print",
    "kb_shot_full_edit": "mod+shift+Print",
    "kb_drift_zoom_in": "mod+equal",
    "kb_drift_zoom_out": "mod+minus",
    "kb_drift_zoom_reset": "mod+0"
}

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

    try:
        ps = subprocess.check_output(["ps", "-u", str(os.getuid()), "-o", "comm="], text=True)
        for wm in ["driftwm", "hyprland", "sway", "niri", "mango"]:
            if wm in ps:
                return wm
    except Exception:
        pass
    return "hyprland"

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

def get_standard_keybindings(compositor):
    settings = load_settings()
    overrides = settings.get("standard_keybindings_overrides", {})

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

    if compositor == "driftwm":
        base.append({"id": "kb_drift_zoom_in", "cat": "windows", "keys": ["Super", "+"], "title": "Приблизить холст", "desc": "Увеличить масштаб бесконечного холста DriftWM"})
        base.append({"id": "kb_drift_zoom_out", "cat": "windows", "keys": ["Super", "-"], "title": "Отдалить холст", "desc": "Уменьшить масштаб холста DriftWM"})
        base.append({"id": "kb_drift_zoom_reset", "cat": "windows", "keys": ["Super", "0"], "title": "Сбросить зум", "desc": "Вернуть 100% масштаб холста DriftWM"})
    elif compositor == "niri":
        base.append({"id": "kb_niri_col_left", "cat": "windows", "keys": ["Super", "H"], "title": "Колонка влево", "desc": "Фокус на колонку слева в ленте Niri"})
        base.append({"id": "kb_niri_col_right", "cat": "windows", "keys": ["Super", "L"], "title": "Колонка вправо", "desc": "Фокус на колонку справа в ленте Niri"})

    for item in base:
        item["defaultKeys"] = list(item["keys"])
        item["exec"] = STANDARD_COMMANDS.get(item["id"], "")
        if item["id"] in overrides:
            ov = overrides[item["id"]]
            if isinstance(ov, str):
                item["keys"] = [k.strip() for k in ov.split("+") if k.strip()]
            elif isinstance(ov, list):
                item["keys"] = ov
            item["isOverridden"] = True
        else:
            item["isOverridden"] = False

    return base

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
    settings = load_settings()
    custom_bindings = settings.get("custom_keybindings", [])
    overrides = settings.get("standard_keybindings_overrides", {})
    home = Path.home()

    # Compile all active bindings to apply
    all_bindings = []
    for b in custom_bindings:
        if b.get("enabled", True):
            all_bindings.append({
                "id": b.get("id"),
                "key": b.get("key", "").strip(),
                "exec": b.get("exec", "").strip(),
                "is_override": False
            })

    for std_id, new_key in overrides.items():
        cmd = STANDARD_COMMANDS.get(std_id, "")
        if cmd and new_key:
            all_bindings.append({
                "id": std_id,
                "key": new_key.strip(),
                "exec": cmd,
                "is_override": True
            })

    if compositor == "hyprland":
        target = home / ".config" / "hypr" / "userprefs.lua"
        lines = []
        for b in all_bindings:
            key = b["key"]
            cmd = b["exec"]
            if not key or not cmd:
                continue
            if cmd == "kill":
                lines.append(f'hl.bind("{key}", hl.dsp.killactive())')
            elif cmd == "fullscreen":
                lines.append(f'hl.bind("{key}", hl.dsp.fullscreen())')
            elif cmd == "floating":
                lines.append(f'hl.bind("{key}", hl.dsp.togglefloating())')
            elif cmd == "center":
                lines.append(f'hl.bind("{key}", hl.dsp.centerwindow())')
            else:
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
        for b in all_bindings:
            raw_key = "".join(b["key"].split())
            key = raw_key.replace("Super", "$mod").replace("super", "$mod")
            cmd = b["exec"]
            if not key or not cmd:
                continue
            if cmd == "kill":
                lines.append(f"bindsym {key} kill")
            elif cmd == "fullscreen":
                lines.append(f"bindsym {key} fullscreen toggle")
            elif cmd == "floating":
                lines.append(f"bindsym {key} floating toggle")
            elif cmd == "center":
                lines.append(f"bindsym {key} move position center")
            else:
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
        for b in all_bindings:
            raw_key = "".join(b["key"].split())
            key = raw_key.replace("Super", "Mod").replace("super", "Mod")
            cmd = b["exec"]
            if not key or not cmd:
                continue
            if cmd == "kill":
                lines.append(f'    {key} {{ close-window; }}')
            elif cmd == "fullscreen":
                lines.append(f'    {key} {{ fullscreen-window; }}')
            elif cmd == "floating":
                lines.append(f'    {key} {{ toggle-window-floating; }}')
            elif cmd == "center":
                lines.append(f'    {key} {{ center-column; }}')
            elif cmd == "focus-column-left":
                lines.append(f'    {key} {{ focus-column-left; }}')
            elif cmd == "focus-column-right":
                lines.append(f'    {key} {{ focus-column-right; }}')
            else:
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
        for b in all_bindings:
            raw_parts = [p.strip() for p in b["key"].split("+") if p.strip()]
            cmd = b["exec"]
            if not raw_parts or not cmd:
                continue
            mods = "+".join(raw_parts[:-1]).upper() if len(raw_parts) > 1 else ""
            k = raw_parts[-1]
            if cmd == "kill":
                lines.append(f"bind={mods},{k},killclient" if mods else f"bind={k},killclient")
            elif cmd == "fullscreen":
                lines.append(f"bind={mods},{k},fullscreen" if mods else f"bind={k},fullscreen")
            elif cmd == "floating":
                lines.append(f"bind={mods},{k},togglefloating" if mods else f"bind={k},togglefloating")
            elif cmd == "center":
                lines.append(f"bind={mods},{k},centerwindow" if mods else f"bind={k},centerwindow")
            else:
                lines.append(f"bind={mods},{k},spawn,{cmd}" if mods else f"bind={k},spawn,{cmd}")

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
        seen_keys = set()
        keys_to_comment = []

        # Comment out old default keys that are overridden
        for std_id in overrides.keys():
            old_def_key = DRIFT_DEFAULT_KEY_MAP.get(std_id)
            if old_def_key:
                keys_to_comment.append(old_def_key.lower())

        for b in all_bindings:
            raw_parts = [p.strip().lower() for p in b["key"].split("+") if p.strip()]
            cmd = b["exec"]
            if not raw_parts or not cmd:
                continue
            parts = [("mod" if p in ("super", "mod4") else p) for p in raw_parts]
            drift_key = "+".join(parts)
            if drift_key in seen_keys:
                continue
            seen_keys.add(drift_key)
            keys_to_comment.append(drift_key)

            if cmd in ("close-window", "kill"):
                lines.append(f'"{drift_key}" = "close-window"')
            elif cmd in ("toggle-fullscreen", "fullscreen"):
                lines.append(f'"{drift_key}" = "toggle-fullscreen"')
            elif cmd in ("toggle-pin-to-screen", "floating"):
                lines.append(f'"{drift_key}" = "toggle-pin-to-screen"')
            elif cmd in ("center-window", "center"):
                lines.append(f'"{drift_key}" = "center-window"')
            elif cmd in ("zoom-in", "zoom-out", "zoom-reset"):
                lines.append(f'"{drift_key}" = "{cmd}"')
            elif cmd.startswith("exec ") or cmd.startswith("spawn "):
                lines.append(f'"{drift_key}" = "{cmd}"')
            else:
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

                # Restore previous overrides
                base = re.sub(r'# \[overridden by userprefs\]\s*', '', base)

                # Comment out any keys that collide or are overridden
                for k in set(keys_to_comment):
                    pattern = rf'^\s*("{re.escape(k)}"\s*=.*)$'
                    base = re.sub(pattern, r'# [overridden by userprefs] \1', base, flags=re.MULTILINE)

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

        env = dict(os.environ)
        if not env.get("WAYLAND_DISPLAY"):
            runtime_dir = Path(env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
            for sock in runtime_dir.glob("wayland-*"):
                if not sock.name.endswith(".lock"):
                    env["WAYLAND_DISPLAY"] = sock.name
                    break
        subprocess.run(["driftwm", "msg", "action", "reload-config"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

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

    elif action in ("override", "edit", "set"):
        target_id = sys.argv[2] if len(sys.argv) > 2 else ""
        new_key = sys.argv[3] if len(sys.argv) > 3 else ""
        new_cmd = sys.argv[4] if len(sys.argv) > 4 else ""
        new_title = sys.argv[5] if len(sys.argv) > 5 else ""

        if not target_id or not new_key:
            print(json.dumps({"error": "ID and key combination required"}))
            sys.exit(1)

        s = load_settings()
        if target_id.startswith("custom_"):
            custom = s.get("custom_keybindings", [])
            for b in custom:
                if b.get("id") == target_id:
                    b["key"] = new_key
                    if new_cmd: b["exec"] = new_cmd
                    if new_title: b["title"] = new_title
                    break
            s["custom_keybindings"] = custom
        else:
            overrides = s.get("standard_keybindings_overrides", {})
            overrides[target_id] = new_key
            s["standard_keybindings_overrides"] = overrides

        save_settings(s)
        sync_userprefs(comp)
        print(json.dumps({"success": True}))

    elif action == "reset":
        target_id = sys.argv[2] if len(sys.argv) > 2 else ""
        if not target_id:
            print(json.dumps({"error": "ID required"}))
            sys.exit(1)

        s = load_settings()
        overrides = s.get("standard_keybindings_overrides", {})
        if target_id in overrides:
            del overrides[target_id]
            s["standard_keybindings_overrides"] = overrides
            save_settings(s)
            sync_userprefs(comp)

        print(json.dumps({"success": True}))

    elif action == "add":
        key = sys.argv[2] if len(sys.argv) > 2 else ""
        cmd = sys.argv[3] if len(sys.argv) > 3 else ""
        title = sys.argv[4] if len(sys.argv) > 4 else cmd
        if not key or not cmd:
            print(json.dumps({"error": "Key and command required"}))
            sys.exit(1)
        s = load_settings()
        custom = s.get("custom_keybindings", [])
        norm_key = "".join(key.split()).lower()
        existing = False
        new_id = ""
        for b in custom:
            if "".join(b.get("key", "").split()).lower() == norm_key:
                b["exec"] = cmd
                b["title"] = title
                b["desc"] = f"Запуск: {cmd}"
                b["enabled"] = True
                new_id = b["id"]
                existing = True
                break
        if not existing:
            import time
            new_id = f"custom_{int(time.time() * 1000)}_{len(custom)}"
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
