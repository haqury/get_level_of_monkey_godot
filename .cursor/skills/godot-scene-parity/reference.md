# Карта проекта и масштаб

Читать, когда фича добавляет локацию, UI или объект, которого ещё нет в сцене.

## Сцены

| scene_id | Файл | Кто грузит |
|---|---|---|
| `main_menu` | `scenes/main_menu/main_menu.tscn` | `SceneManager`, главная сцена `project.godot` |
| `game_session` | `scenes/game/game_session.tscn` | оболочка: `World`, `Player`, `RemotePlayer`, `Camera2D` |
| `cave` | `scenes/cave/cave.tscn` | инстанс в `World` |
| `kitchen` | `scenes/kitchen/kitchen.tscn` | инстанс в `World` |
| `minigame` | `scenes/minigame/minigame.tscn` | инстанс в `World`; статика ещё в коде — переносить в сцену |

Пути только из `SceneManager.SCENE_PATHS`. Новый id без записи туда не появится в игре.

Автолоады: `ConfigLoader`, `GameBootstrap`, `GameState`, `I18n`, `SaveManager`, `ProgressionSystem`, `InputManager`, `NetworkManager`, `SceneManager`, `BrainLinkBridge`, `GameUI` (`scenes/ui/game_ui.tscn`).

Окно: 1280×720, stretch `canvas_items`.

## Формулы

`DESIGN_PPU = 24` (`BaseLocation.DESIGN_PPU`). `GameState.PIXELS_PER_UNIT` стартует с 24 и может измениться в `fit_pixels_per_unit_to_viewport`.

Позиция в `.tscn`:

```
position_px = game_units * 24
```

Пример из пещеры: пол 70×36, стена сверху на `y = 18 * 24 = 432`, выход на кухню `x = 32 * 24 = 768`.

Масштаб корня локации в игре (в редакторе множитель не ставится):

```
scale = GameState.PIXELS_PER_UNIT / 24
```

`SceneSprite` при `tiled = false` ставит масштаб текстуры `size_units * 24 / texture_size`. При `tiled = true` включает `region` размером `size_units * 24` и `TEXTURE_REPEAT_MIRROR`, `scale = (1, 1)`.

Игрок вне локации, поэтому его радиус и спрайт считаются от `GameState.PIXELS_PER_UNIT` (`player.gd` → `apply_viewport_scale`).

## Узлы, которые уже умеют совпадать

| Узел | Скрипт | Роль |
|---|---|---|
| Спрайт декора | `scripts/world/scene_sprite.gd` | `@tool`, размер в единицах виден в редакторе |
| Локация | `scripts/world/base_location.gd` | собирает NPC из `NPCs`, масштаб корня только в игре |
| Выход | `scenes/world/exit_area.tscn` | `Area2D`, мета `exit_info` из экспортов |
| NPC | `scenes/npc/npc.tscn` | диалог и текстура из экспортов инстанса |
| Тема UI | `scripts/ui/game_ui_theme.gd` | `apply_editor_preview`, `sync_edited_scene_root` |
| Превью | `addons/ui_theme_editor/plugin.gd` | на `scene_changed` синхронизирует открытую сцену |

`z_index`: фон локации `-10` (ставит `BaseLocation`), сущности мини-игры `5`.

## Динамика, которой нет в сцене до старта волны

Обезьяны и снаряды (`minigame.gd`) создаются по данным `MinigameSim`. Цель при доработке: спрайт обезьяны и спрайт снаряда — packed scene с текстурой; код только расставляет экземпляры в `Entities`. Позиция экземпляра внутри уже масштабированной локации — `units * 24`, не `GameState.units_to_px`.

`WorldVisuals.solid_sprite` / `floor_sprite` — запасной путь, пока текстуры нет. Новый видимый объект им не заводить.

## UI

Дерево `game_ui.tscn`: `HUD` (панель, Top10), `Dialog`, пауза, инстансы настроек. Скрипт `autoload/game_ui.gd` показывает и прячет готовые блоки и дописывает кнопки вариантов диалога в существующий контейнер.

Настройки и BrainLink: контейнер строк в сцене, наполнение в `_build_editor_dynamic_content`, то же наполнение в игре. Редактор вызывает это из `ensure_editor_preview_content`, когда сцена — корень редактирования (`GameUiTheme.is_edited_scene_root`).
