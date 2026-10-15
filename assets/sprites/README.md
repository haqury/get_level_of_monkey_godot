# Sprites

### Player (`player/`)
- **source_spritesheet_original.jpg** — исходный лист с нимбом. Не перезаписывать.
- **source_spritesheet.png** — новый лист, прозрачный фон (RGBA). 4 колонки: down, left, right, up. 6 рядов: idle и 5 кадров ходьбы. Без нимба.
- **idle/** и **walk/** — те же кадры по файлам (`{dir}_1` … `{dir}_5`).
- JPG не умеет прозрачность, поэтому новый лист именно `.png`.

Пересборка:

```bash
python tools/regenerate_player_from_sheet.py
```

После этого в Godot: **Project → Reload Current Project**.
