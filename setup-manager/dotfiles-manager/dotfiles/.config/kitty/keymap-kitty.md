# Kitty — гарячі клавіші (Keymap)

> Довідник для **Arch Linux / KDE Plasma / Wayland**, із рекомендаціями для **Neovim, Snacks, ZSH та CLI**.
>
> **Стандартні** комбінації наведені для Kitty з типовими налаштуваннями. **Власні** комбінації із розділу 8 потрібно додати до `kitty.conf`.

## 1. Модифікатори

| Назва | Клавіші | Опис |
|---|---|---|
| `kitty_mod` | `Ctrl + Shift` | Стандартний модифікатор Kitty |
| `ctrl` | `Ctrl` | Control |
| `shift` | `Shift` | Shift |
| `alt` | `Alt` | Alt |
| `super` | `Super` | Клавіша Windows / Meta |

У конфігурації типовий модифікатор задається так:

```conf
kitty_mod ctrl+shift
```

## 2. Вкладки (Tabs) — стандартні

| Клавіші | Дія |
|---|---|
| `Ctrl + Shift + T` | Створити вкладку |
| `Ctrl + Shift + Q` | Закрити поточну вкладку |
| `Ctrl + Shift + →` або `Ctrl + Tab` | Наступна вкладка |
| `Ctrl + Shift + ←` або `Ctrl + Shift + Tab` | Попередня вкладка |
| `Ctrl + Shift + .` | Перемістити вкладку вперед |
| `Ctrl + Shift + ,` | Перемістити вкладку назад |
| `Ctrl + Shift + Alt + T` | Перейменувати вкладку |

## 3. Панелі та вікна Kitty — стандартні

> **Важливо:** «вікно Kitty» (*kitty window*) всередині вкладки — це термінальна панель, а **OS window** — окреме вікно KDE.

| Клавіші | Дія |
|---|---|
| `Ctrl + Shift + Enter` | Створити панель у поточній вкладці |
| `Ctrl + Shift + W` | Закрити поточну панель |
| `Ctrl + Shift + ]` | Наступна панель |
| `Ctrl + Shift + [` | Попередня панель |
| `Ctrl + Shift + N` | Створити окреме вікно ОС |
| `Ctrl + Shift + L` | Перемкнути схему розташування панелей (`next_layout`) |
| `Ctrl + Shift + F` | Перемістити панель вперед |
| `Ctrl + Shift + B` | Перемістити панель назад |

Спосіб розміщення нових панелей залежить від поточного **layout**. У Kitty є `splits`, `tall`, `fat`, `grid`, `stack` та інші режими.

## 4. Буфер обміну та посилання — стандартні

| Клавіші | Дія |
|---|---|
| `Ctrl + Shift + C` | Копіювати виділений текст |
| `Ctrl + Shift + V` | Вставити з буфера обміну |
| `Ctrl + Shift + S` | Вставити з primary selection (Linux) |
| `Ctrl + Shift + E` | Вибрати URL для відкриття |
| `Ctrl + Shift + U` | Ввести Unicode-символ |

## 5. Шрифт і відображення — стандартні

| Клавіші | Дія |
|---|---|
| `Ctrl + Shift + =` | Збільшити шрифт |
| `Ctrl + Shift + -` | Зменшити шрифт |
| `Ctrl + Shift + Backspace` | Повернути стандартний розмір шрифту |
| `Ctrl + Shift + F11` | Повноекранний режим |
| `Ctrl + Shift + F10` | Розгорнути / відновити вікно |
| `Ctrl + Shift + Delete` | Скинути стан термінала |

Прозорість фону керується послідовними комбінаціями (спочатку `Ctrl + Shift + A`, потім друга клавіша):

| Послідовність | Дія |
|---|---|
| `Ctrl + Shift + A`, потім `M` | Збільшити непрозорість |
| `Ctrl + Shift + A`, потім `L` | Зменшити непрозорість |
| `Ctrl + Shift + A`, потім `1` | Повністю непрозорий фон |
| `Ctrl + Shift + A`, потім `D` | Повернути стандартну непрозорість |

## 6. Налаштування та інструменти — стандартні

| Клавіші | Дія |
|---|---|
| `Ctrl + Shift + F1` | Відкрити документацію |
| `Ctrl + Shift + F2` | Редагувати `kitty.conf` |
| `Ctrl + Shift + F3` | Палітра команд Kitty |
| `Ctrl + Shift + F5` | Перезавантажити конфігурацію |
| `Ctrl + Shift + F6` | Переглянути діагностику конфігурації |
| `Ctrl + Shift + Esc` | Відкрити Kitty Shell |

**Порада:** через `Ctrl + Shift + F3` зручно знайти доступні дії та їхні клавіші.

## 7. Де зберігається конфігурація

Основний файл:

```text
~/.config/kitty/kitty.conf
```

За потреби клавіші можна винести в окремий файл:

```text
~/.config/kitty/keymaps.conf
```

І підключити його у `kitty.conf`:

```conf
include keymaps.conf
```

## 8. Рекомендовані власні клавіші в стилі Vim

Наведені нижче прив'язки **не всі є стандартними**. Додай їх у `~/.config/kitty/keymaps.conf` (а потім `include keymaps.conf` у `kitty.conf`) або безпосередньо в `kitty.conf`.

```conf
# ============================================================
# KITTY KEYMAP — ARCH / KDE / NEOVIM
# ============================================================

# Залишаємо типовий модифікатор
kitty_mod ctrl+shift

# Вкладки
map --allow-fallback=shifted,ascii kitty_mod+t new_tab
map --allow-fallback=shifted,ascii kitty_mod+q close_tab

# Панелі
map kitty_mod+enter new_window
map --allow-fallback=shifted,ascii kitty_mod+w close_window

# Переміщення між панелями (Vim-style)
map --allow-fallback=shifted,ascii kitty_mod+h neighboring_window left
map --allow-fallback=shifted,ascii kitty_mod+j neighboring_window down
map --allow-fallback=shifted,ascii kitty_mod+k neighboring_window up
map --allow-fallback=shifted,ascii kitty_mod+l neighboring_window right

# Оскільки Ctrl+Shift+L тепер зайнято напрямком right,
# перемикання layout переносимо на Ctrl+Shift+Space
map kitty_mod+space next_layout

# Перезавантаження конфіга
map kitty_mod+f5 load_config_file
```

### Рекомендована навігація

| Клавіші | Результат | Статус |
|---|---|---|
| `Ctrl + Shift + H` | Панель ліворуч | Власна |
| `Ctrl + Shift + J` | Панель знизу | Власна |
| `Ctrl + Shift + K` | Панель зверху | Власна |
| `Ctrl + Shift + L` | Панель праворуч | Власна, замінює `next_layout` |
| `Ctrl + Shift + Space` | Наступний layout | Власна |

> **Neovim:** залиш `Ctrl + H/J/K/L` для переміщення між вікнами всередині Neovim, а `Ctrl + Shift + H/J/K/L` — для панелей Kitty. Це зменшує кількість конфліктів із Neovim / Snacks.

### Налаштування розміщення панелей

Якщо потрібні саме горизонтальні та вертикальні поділи, додай до `kitty.conf`:

```conf
enabled_layouts splits,tall,fat,grid,stack
```

У такому випадку перший layout (`splits`) буде типовим. Команда `new_window` створює панель відповідно до активного layout; для точного спрямування розділення можна налаштувати окремі команди `launch --location=hsplit` і `launch --location=vsplit` у layout `splits`.

## 9. Застосування та перевірка

Відкрий налаштування:

```bash
nvim ~/.config/kitty/kitty.conf
```

Після збереження натисни:

```text
Ctrl + Shift + F5
```

Перевірити помилки конфігурації можна через `Ctrl + Shift + F6`. Для перегляду натиснутих клавіш:

```bash
kitten show-key -m kitty
```

Або для діагностики клавіатурних подій запусти окремий Kitty:

```bash
kitty --debug-input
```

**Зауваження для KDE Plasma / Wayland:** системні глобальні комбінації можуть перехоплюватися Plasma раніше, ніж Kitty. Якщо клавіша не працює, перевір `Системні параметри → Клавіатура → Комбінації клавіш`.

## 10. Офіційна документація

- [Kitty: Configuration](https://sw.kovidgoyal.net/kitty/conf/)
- [Kitty: Mappable actions](https://sw.kovidgoyal.net/kitty/actions/)
- [Kitty: Keyboard mapping](https://sw.kovidgoyal.net/kitty/mapping/)
- [Kitty: Layouts](https://sw.kovidgoyal.net/kitty/layouts/)

---

**Коротко:** для щоденної роботи використовуй `Ctrl + Shift + T` (вкладка), `Ctrl + Shift + Enter` (панель), `Ctrl + Shift + W` (закрити панель), `Ctrl + Shift + F3` (палітра команд), а після додавання власного конфіга — `Ctrl + Shift + H/J/K/L` (навігація між панелями).
