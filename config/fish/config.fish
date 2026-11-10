# ~/.config/fish/config.fish
# Serpantinum + SelionOS prompt config

# Отключение стандартного приветствия
set -g fish_greeting ""

# Переменные окружения
set -gx EDITOR nano
set -gx VISUAL nano
set -gx PAGER "bat --plain"
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

# Пути
fish_add_path ~/.local/bin ~/.cargo/bin /usr/local/bin

# Динамическая загрузка цветов из темы Serpantinum (Matugen или Static Preset)
function _update_serp_theme
    set -l s_file "$HOME/.config/serpantinum/settings.json"
    set -l q_file "$HOME/.local/state/serpantinum/qs_colors.json"

    set -l m1 (path mtime "$s_file" 2>/dev/null; or echo 0)
    set -l m2 (path mtime "$q_file" 2>/dev/null; or echo 0)
    set -l cur_mtimes "$m1:$m2"

    if test "$cur_mtimes" != "$_serp_theme_mtimes"
        set -g _serp_theme_mtimes "$cur_mtimes"
        set -l parsed (python3 ~/.local/bin/serpantinum_theme_sync.py --fish-vars 2>/dev/null)
        set -l colors (string split " " "$parsed")

        if test (count $colors) -ge 6
            set -g _serp_c_frame $colors[1]
            set -g _serp_c_user  $colors[2]
            set -g _serp_c_at    $colors[3]
            set -g _serp_c_err   $colors[4]

            # Синхронизация подсветки синтаксиса Fish с темой
            set -g fish_color_normal $colors[5]
            set -g fish_color_command $colors[1] --bold
            set -g fish_color_keyword $colors[2] --bold
            set -g fish_color_quote $colors[2]
            set -g fish_color_redirection $colors[1]
            set -g fish_color_end $colors[4]
            set -g fish_color_error $colors[4]
            set -g fish_color_param $colors[5]
            set -g fish_color_comment $colors[3]
            set -g fish_color_selection --background=$colors[6]
            set -g fish_color_search_match --background=$colors[6]
            set -g fish_color_operator $colors[1]
            set -g fish_color_escape $colors[2]
            set -g fish_color_autosuggestion $colors[3]
            set -g fish_color_cancel $colors[4]
            set -g fish_pager_color_prefix $colors[1] --bold
            set -g fish_pager_color_completion $colors[5]
            set -g fish_pager_color_description $colors[3]
            set -g fish_pager_color_progress $colors[2]
            set -g fish_pager_color_selected_background --background=$colors[6]
        end
    end
end

# Мгновенная перерисовка при получении сигнала от смены темы (SIGUSR1 / WINCH)
function _serp_on_signal --on-signal USR1 --on-signal WINCH
    _update_serp_theme
    commandline -f repaint 2>/dev/null
end

# Инициализация цветов при запуске
_update_serp_theme

# Функция-обертка для fastfetch с отступом в 1 строчку сверху (стиль SelionOS)
function fastfetch
    echo ""
    command fastfetch $argv
end

# Универсальный выход из графической сессии (Hyprland / Sway / DriftWM) в SDDM
function logout --description "Выход из графической сессии в SDDM"
    if set -q HYPRLAND_INSTANCE_SIGNATURE
        hyprctl dispatch exit 2>/dev/null; or hyprctl dispatch "hl.dsp.exit()" 2>/dev/null; or loginctl terminate-user $USER
    else if set -q SWAYSOCK; or pgrep -x sway >/dev/null
        swaymsg exit 2>/dev/null; or loginctl terminate-user $USER
    else if command -v driftwm >/dev/null; and test -n "$DRIFTWM_SOCKET"
        driftwm msg action quit 2>/dev/null; or loginctl terminate-user $USER
    else
        loginctl terminate-user $USER
    end
end

# Кастомный prompt (стиль SelionOS с динамическими цветами Serpantinum)
function fish_prompt
    set -l last_status $status

    # Проверяем, изменилась ли тема
    _update_serp_theme

    # Отступ в 1 строчку между командами
    echo ""

    # Палитра из темы:
    set -l color_icon  (set_color --bold $_serp_c_frame)
    set -l color_frame (set_color $_serp_c_frame)
    set -l color_user  (set_color --bold $_serp_c_user)
    set -l color_at    (set_color $_serp_c_at)
    set -l color_cwd   (set_color --bold $_serp_c_frame)
    set -l color_arrow (set_color $_serp_c_frame)
    if test $last_status -ne 0
        set color_arrow (set_color $_serp_c_err)
    end
    set -l color_reset (set_color normal)

    # Замена домашнего каталога на тильду ~
    set -l cwd (string replace -r "^$HOME" "~" "$PWD")

    # Первая строка: ╭─  имя_пользователя at путь
    echo -s $color_frame "╭─" $color_icon "  " $color_user $USER " " $color_at "at " $color_cwd $cwd $color_reset

    # Вторая строка: ╰─▸ 
    echo -n -s $color_frame "╰─" $color_arrow "▸ " $color_reset
end

# Полезные алиасы
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first"
alias la="eza -a --icons --group-directories-first"
alias lt="eza --tree --level=2 --icons"
alias cat="bat --paging=never --style=plain"
alias grep="grep --color=auto"

# Алиасы пакетов
alias pac="sudo pacman -S"
alias pacu="sudo pacman -Syu"
alias pacs="pacman -Ss"
alias paci="pacman -Qi"
alias pacr="sudo pacman -Rns"

# Алиасы для рисования и WM
alias serp="serpantinum"
alias drift="driftwm msg"
alias ff="fastfetch"
alias power="battery"

# Интерактивные интеграции и приветствие
if status is-interactive
    # Умный cd (zoxide)
    if type -q zoxide
        zoxide init fish | source
    end

    # FZF
    if type -q fzf
        fzf --fish | source
    end

    # Запуск fastfetch при старте (стиль SelionOS)
    fastfetch
end
