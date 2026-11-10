# ============================================================
# ZSH PLUGINS — NORDIC THEME
# Підказки команд та підсвічування синтаксису.
# ============================================================

# ------------------------------------------------------------
# ОСНОВНІ КОЛЬОРИ
# ------------------------------------------------------------

typeset -g ZSH_NORDIC_WHITE='#D8DEE9'  # Основний світлий текст
typeset -g ZSH_NORDIC_GRAY='#616E88'   # Приглушений сіро-синій
typeset -g ZSH_NORDIC_RED='#BF616A'    # Червоний
typeset -g ZSH_NORDIC_ORANGE='#D08770' # Помаранчевий
typeset -g ZSH_NORDIC_YELLOW='#EBCB8B' # Жовтий
typeset -g ZSH_NORDIC_GREEN='#A3BE8C'  # Зелений
typeset -g ZSH_NORDIC_PURPLE='#B48EAD' # Фіолетовий
typeset -g ZSH_NORDIC_BLUE='#61AFEF'   # Синій
# typeset -g ZSH_NORDIC_BLUE='#81A1C1'      # Синій
typeset -g ZSH_NORDIC_CYAN='#88C0D0'      # Блакитний
typeset -g ZSH_NORDIC_TEAL='#8FBCBB'      # Бірюзовий
typeset -g ZSH_NORDIC_DARK_BLUE='#5E81AC' # Темно-синій

# ============================================================
# ZSH AUTOSUGGESTIONS
# Підказки команд на основі історії.
# ============================================================

# Колір тексту запропонованої команди.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=${ZSH_NORDIC_GRAY}"

if [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# ============================================================
# ZSH SYNTAX HIGHLIGHTING
# Підсвічування синтаксису команд.
# ============================================================

# Створити асоціативний масив стилів.
typeset -gA ZSH_HIGHLIGHT_STYLES

# ------------------------------------------------------------
# КОМАНДИ
# ------------------------------------------------------------

# Звичайні команди.
ZSH_HIGHLIGHT_STYLES[command]="fg=${ZSH_NORDIC_GREEN},bold"

# Вбудовані команди ZSH.
ZSH_HIGHLIGHT_STYLES[builtin]="fg=${ZSH_NORDIC_GREEN}"

# Функції.
ZSH_HIGHLIGHT_STYLES[function]="fg=${ZSH_NORDIC_GREEN}"

# Аліаси.
ZSH_HIGHLIGHT_STYLES[alias]="fg=${ZSH_NORDIC_CYAN}"

# Попередні команди та модифікатори.
ZSH_HIGHLIGHT_STYLES[precommand]="fg=${ZSH_NORDIC_GREEN}"

# Команди з кешу ZSH.
ZSH_HIGHLIGHT_STYLES['hashed-command']="fg=${ZSH_NORDIC_GREEN}"

# Невідомі команди та помилкові токени.
ZSH_HIGHLIGHT_STYLES['unknown-token']="fg=${ZSH_NORDIC_RED},bold"

# ------------------------------------------------------------
# ПАРАМЕТРИ КОМАНД
# ------------------------------------------------------------

# Параметри з одним дефісом: -S, -R, -h.
ZSH_HIGHLIGHT_STYLES['single-hyphen-option']="fg=${ZSH_NORDIC_CYAN}"

# Параметри з двома дефісами: --help, --needed.
ZSH_HIGHLIGHT_STYLES['double-hyphen-option']="fg=${ZSH_NORDIC_CYAN}"

# ------------------------------------------------------------
# ШЛЯХИ ТА ФАЙЛИ
# ------------------------------------------------------------

# Існуючі шляхи до файлів і каталогів.
ZSH_HIGHLIGHT_STYLES[path]="fg=${ZSH_NORDIC_BLUE}"

# Частини шляхів, які ще не завершені.
ZSH_HIGHLIGHT_STYLES[path_prefix]="fg=${ZSH_NORDIC_BLUE}"

# Роздільники шляхів.
ZSH_HIGHLIGHT_STYLES[path_pathseparator]="fg=${ZSH_NORDIC_CYAN}"

# Роздільники незавершених шляхів.
ZSH_HIGHLIGHT_STYLES[path_prefix_pathseparator]="fg=${ZSH_NORDIC_CYAN}"

# ------------------------------------------------------------
# ТЕКСТОВІ АРГУМЕНТИ
# ------------------------------------------------------------

# Аргументи в одинарних лапках.
ZSH_HIGHLIGHT_STYLES['single-quoted-argument']="fg=${ZSH_NORDIC_YELLOW}"

# Аргументи в подвійних лапках.
ZSH_HIGHLIGHT_STYLES['double-quoted-argument']="fg=${ZSH_NORDIC_YELLOW}"

# Аргументи у форматі $'...'.
ZSH_HIGHLIGHT_STYLES['dollar-quoted-argument']="fg=${ZSH_NORDIC_YELLOW}"

# Незакриті одинарні лапки.
ZSH_HIGHLIGHT_STYLES['single-quoted-argument-unclosed']="fg=${ZSH_NORDIC_RED},bold"

# Незакриті подвійні лапки.
ZSH_HIGHLIGHT_STYLES['double-quoted-argument-unclosed']="fg=${ZSH_NORDIC_RED},bold"

# ------------------------------------------------------------
# ЗМІННІ ТА ПРИСВОЮВАННЯ
# ------------------------------------------------------------

# Присвоювання змінних: NAME=value.
ZSH_HIGHLIGHT_STYLES[assign]="fg=${ZSH_NORDIC_ORANGE}"

# Змінні всередині подвійних лапок: "$HOME".
ZSH_HIGHLIGHT_STYLES['dollar-double-quoted-argument']="fg=${ZSH_NORDIC_ORANGE}"

# Екрановані символи всередині подвійних лапок.
ZSH_HIGHLIGHT_STYLES['back-double-quoted-argument']="fg=${ZSH_NORDIC_TEAL}"

# Екрановані символи всередині $'...'.
ZSH_HIGHLIGHT_STYLES['back-dollar-quoted-argument']="fg=${ZSH_NORDIC_TEAL}"

# ------------------------------------------------------------
# ЗАРЕЗЕРВОВАНІ СЛОВА ZSH
# ------------------------------------------------------------

# Керуючі конструкції: if, then, else, fi, for, while.
ZSH_HIGHLIGHT_STYLES['reserved-word']="fg=${ZSH_NORDIC_DARK_BLUE},bold"

# ------------------------------------------------------------
# ОПЕРАТОРИ
# ------------------------------------------------------------

# Роздільники команд: ;, &&, ||, |.
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=${ZSH_NORDIC_TEAL},bold"

# Перенаправлення введення та виведення: >, >>, <.
ZSH_HIGHLIGHT_STYLES[redirection]="fg=${ZSH_NORDIC_TEAL}"

# Шаблони пошуку: *, ?, [abc].
ZSH_HIGHLIGHT_STYLES[globbing]="fg=${ZSH_NORDIC_PURPLE}"

# Підстановка команд: $(...).
ZSH_HIGHLIGHT_STYLES['command-substitution']="fg=${ZSH_NORDIC_TEAL}"

# Дужки підстановки команд.
ZSH_HIGHLIGHT_STYLES['command-substitution-delimiter']="fg=${ZSH_NORDIC_CYAN}"

# ------------------------------------------------------------
# ІСТОРІЯ КОМАНД ТА КОМЕНТАРІ
# ------------------------------------------------------------

# Розширення історії: !команда.
ZSH_HIGHLIGHT_STYLES['history-expansion']="fg=${ZSH_NORDIC_PURPLE}"

# Коментарі.
ZSH_HIGHLIGHT_STYLES[comment]="fg=${ZSH_NORDIC_GRAY}"

# ------------------------------------------------------------
# ІНШІ ЕЛЕМЕНТИ
# ------------------------------------------------------------

# Звичайний текст, для якого немає окремого стилю.
ZSH_HIGHLIGHT_STYLES[default]="fg=${ZSH_NORDIC_WHITE}"

# Іменовані файлові дескриптори.
ZSH_HIGHLIGHT_STYLES['named-fd']="fg=${ZSH_NORDIC_ORANGE}"

# Числові файлові дескриптори.
ZSH_HIGHLIGHT_STYLES['numeric-fd']="fg=${ZSH_NORDIC_PURPLE}"

# ============================================================
# ЗАВАНТАЖЕННЯ SYNTAX HIGHLIGHTING
# Цей плагін повинен завантажуватися останнім серед плагінів ZLE.
# ============================================================

if [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
