# Umbriel — Руководство по управлению и настройке

**Umbriel** — лёгкий Wayland-композитор на wlroots со скроллируемым ленточным тайлингом (scrolling layout), альтернативными раскладками (`scrolling`, `dwindle`, `master`, `stacking`), scratchpad-карманом, горячими углами и TOML-конфигурацией с модульными include-файлами.

---

## Структура конфигурации

Все настройки находятся в `~/.config/umbriel/`:
- `config.toml` — точка входа, переменные окружения и подключения (`[include]` и `[include.optional]`);
- `config/input.toml` — раскладки клавиатуры (`us,ru`, `alt_shift_toggle`), тачпад (`flat`, `clickfinger`, natural scroll) и курсор;
- `config/layout.toml` — отступы и базовые параметры внешнего вида;
- `config/windowrules.toml` — правила окон (Picture-in-Picture, плавающие диалоги и системные утилиты);
- `config/autostart.toml` — запуск `serpantinumd` и буфера обмена `cliphist`;
- `config/keybinds.toml` — единые сочетания клавиш Selion;
- `config/monitors.toml` — параметры мониторов (управляются через Настройки -> Дисплей);
- `userprefs.toml` и `workflows/` — ваши личные настройки и режимы (`default.toml`, `gaming.toml`, `powersaver.toml`), сохраняющиеся при обновлениях.

Проверить конфигурацию без перезапуска можно командой:
`umbriel config validate -c ~/.config/umbriel/config.toml`

Подробная документация: [docs/configure/compositors/umbriel.md](../../docs/configure/compositors/umbriel.md).
