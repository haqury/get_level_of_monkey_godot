# Get Level of Monkey — спецификация для реализации на Godot

Документ описывает **текущую** реализацию (Python + Panda3D) как **дизайн- и техническое ТЗ** для переноса в другой репозиторий на **Godot 4.x** (2D, вид сверху). Цель — воспроизвести геймплей, системы, сеть и опционально BrainLink без привязки к Panda3D.

---

## 1. Кратко о продукте

| Поле | Значение |
|------|----------|
| **Жанр** | 2D action / light RPG, камера сверху (orthographic) |
| **Сеттинг** | Дом/пещера ребёнка («карапуз»), кухня, «улица» — мини-игра с обезьянами |
| **Уникальность** | Управление с клавиатуры **или** через **BrainLink** (Shared Memory + ML-предсказания) |
| **Режимы** | Solo, **кооп 2 игрока по LAN** (хост + клиент) |
| **Локализация** | RU / EN (JSON-ключи) |
| **Платформа (оригинал)** | Windows, standalone exe + zip |

**Название окна (конфиг):** настраивается; в репозитории встречается рабочее имя проекта `get_level_of_monkey`, заголовок окна в `game_config.json` может отличаться.

---

## 2. Игровой цикл

1. **Главное меню** — solo / сетевая игра / настройки / BrainLink / выход.
2. **Старт игры** → локация **Cave** (пещера).
3. Исследование: диалоги с NPC, трата **энергии** на движение, **HP** в мини-игре.
4. **Выходы (триггеры)** на границах комнат → переход в **Kitchen** или запуск цепочки **Minigame**.
5. **Мини-игра** — выживание, XP, таблица рекордов; выход обратно в пещеру (exit в сцене minigame).
6. **Пауза (ESC / P)** — рестарт этапа (minigame), загрузка, настройки, выход в меню.
7. **Автосохранение** при смене сцены (solo / host; **не** на клиенте в коопе).

---

## 3. Сцены (локации)

Идентификаторы сцен (строки, единый `SceneManager`):

| `scene_id` | Название | Описание |
|------------|----------|----------|
| `main_menu` | Main Menu | UI, не игровой мир |
| `cave` | Cave | Стартовая локация |
| `kitchen` | Kitchen | Кухня с мамой |
| `minigame` | Minigame | «Обезьянья атака» |

### 3.1. Cave (пещера)

- **Размер пола (игровые единицы):** примерно **70×36** (X: −35…35, Z/ Y: −18…18). Стены по периметру, толщина ~3.
- **NPC:** **Father** (Отец), позиция ~ (−10, 10).
- **Выходы** (радиус срабатывания ~**3.0** от центра игрока):
  - `to_kitchen`: pos **(32, 0)** → `kitchen`
  - `to_outside` / minigame: pos **(−32, 0)** → `minigame` (не мгновенный переход — см. диалоги)
- **Спрайты:** `assets/sprites/cave/cave_floor.png`, `cave_wall.png`, маркеры выхода `cave_exit.png`, `cave_door.png`.
- **Диалоги отца (Space у NPC):** две реплики по ключам i18n `npc.father.dialog1`, `dialog2`.
- **Выход «на улицу»:** если у выхода есть Father — показывается **exit-диалог** отца; иначе сразу выбор режима мини-игры.

### 3.2. Kitchen (кухня)

- **Размер:** примерно **100×60** (frame −50…50, −30…30).
- **NPC:** **Mother** ~ (10, 0), анимация готовки (переключение `mother.png` / `mother_cook1.png` ~ каждые 0.5 с).
- **Декор:** спрайты `kitchen/stove`, `fridge`, `microwave`, `counter`, `sink`.
- **Выход:** `to_cave` at **(−25, 0)** → `cave`.
- **Диалоги:** `npc.mother.dialog1`, `dialog2`.

### 3.3. Minigame (обезьянья атака)

**Визуальная структура:**

- Фон «лес» — тот же масштаб, что пещера: **−35…35 × −18…18** (`forest_floor.png`).
- **Поляна (clearing)** в центре: **60×30** (half-w=30, half-h=15).
- **Дороги (road)** по краям поляны, ширина полосы **ROAD_WIDTH = 2.5** — по ним ходят обезьяны; **игрок не может ступать на дорогу** (коллизия).
- **Лес (bushes/walls)** — полосы за пределами поляны; игрок не заходит в лес.
- **Играемая зона игрока:** внутренний прямоугольник поляны минус дорога:

```text
min_x = -CLEARING_HALF_W + ROAD_WIDTH   # -27.5
max_x =  CLEARING_HALF_W - ROAD_WIDTH   #  27.5
min_y = -CLEARING_HALF_H + ROAD_WIDTH   # -12.5
max_y =  CLEARING_HALF_H - ROAD_WIDTH   #  12.5
```

**Режимы (`monkey_mode`):**

| Режим | Обезьяны | Бросок |
|-------|----------|--------|
| `NorthSouth` | Идут вдоль **верхнего/нижнего** края (горизонтальное движение) | Перpendicular: летит вдоль **Z**, фиксированный X |
| `WestEast` | Идут вдоль **левого/правого** края (вертикальное движение) | Перpendicular: летит вдоль **X**, фиксированный Z |

**Спавн волн:**

- Старт: группа из **1** обезьяны.
- Когда обезьяна доходит до конца пути и **despawn** — размер следующей группы **+1**, максимум **5**.
- Новая группа спавнится только когда **на поле 0 обезьян**.
- Обезьяны появляются **в лесу** за краем поляны и выходят на дорогу.

**Обезьяны (возраст 1–4):**

- Визуал: `assets/sprites/monkey/age{N}.png` (есть также run/throw — в оригинале частично).
- Параметры из `balance.json` → `minigame.monkeys.stats_by_age`: `throw_speed`, `accuracy`, `cooldown`.
- Кулдаун броска в коде уменьшен (~×0.4 от конфига).
- Бросок только если игрок в playable area и «в одной полосе» с обезьяной (threshold ~15 единиц).

**Какашки (Poops):**

- Спрайт `minigame/poop.png`, радиус попадания ~**0.5**.
- Скорость: `balance.minigame.poop.speed` (300) / 15 ≈ **20 u/s** × множители возраста.
- Lifetime **5 с**; вылет за границу clearing — исчезает.
- Урон **1 HP**; промах → XP за уклонение (`xp_per_dodge`).

**Прогрессия в minigame:**

- XP за секунду выживания и за уклонения (см. `balance.progression`).
- HUD: таймер выживания.
- **Top 10** справа (solo/host): лучшие забеги **без cheater** по режиму; данные из `saves/minigame_stats.json`.
- **Game over** при HP=0: сохранение времени, run в stats, событие в BrainLink ML (если включено).

**Выход из minigame:** exit `to_cave` at **(0, −25)**.

---

## 4. Игрок

- **Вид:** billboarding sprite (в Godot — `AnimatedSprite2D` / 4 направления walk + idle down).
- **Спрайты:** `assets/sprites/player/walk/{up,down,left,right}.png`, `idle/down.png`.
- **Скорость:** `game_config.player.move_speed` (default **5**).
- **Коллизия:** радиус ~0.5; границы сцены + объекты (стены пещеры, лес/дорога в minigame).
- **Состояния:** `facing` (up/down/left/right), `is_moving`, `is_sitting` (удержание action — визуально squash scale Z).
- **Сидение:** удержание **Space** (action): regen энергии **×2**, движение блокируется; в BrainLink периодически шлётся `stop` для ML/истории.

**Энергия:**

- Max/regen из конфига; трата при движении (`move_cost` в конфиге — в оригинале завязано на логику движения).
- **`cheater_mode`:** бесконечная энергия (настройка игрока).

**HP:**

- В exploration — в основном через minigame; `initial_hp` (default **3**).

---

## 5. NPC и диалоги

**Базовый NPC:**

- Радиус взаимодействия **~10** (масштаб «×5» локаций).
- **Space** рядом с NPC → `DialogBox`: текст, кнопка «Далее» или список **options** (text + callback).

**Father — цепочка minigame (только у хоста / solo):**

1. Игрок (локальный или **remote** в коопе) заходит в exit → minigame.
2. Диалог отца (`npc.father.exit`): опции **«Мини-игра»** и **«Отмена»** (требование UX: хост может отказаться; если оба игрока покинули зону exit — диалог закрывается).
3. После согласия — диалог выбора режима: **NorthSouth**, **WestEast**, **Отмена**.
4. Старт → `switch_scene("minigame", monkey_mode=...)`.

**Клиент в коопе:** не инициирует смену сцен локально; ждёт `scene_change` от хоста.

---

## 6. UI

| Компонент | Содержимое |
|-----------|------------|
| **HUD** | HP, энергия, уровень, ML-блок (pred/conf/probs), таймер выживания (minigame) |
| **DialogBox** | Имя NPC, текст, options или Continue |
| **PauseMenu** | Restart (minigame), Load, Settings, BrainLink settings, Exit to menu |
| **Main menu** | Play solo, Network submenu (Host/Join), settings, BrainLink status, quit |

**Клавиши (defaults):**

- Движение: стрелки (rebindable).
- Action / dialog: **Space**.
- Sit + pause menu: **P** (и ESC для паузы в игре).

---

## 7. Прогression и сохранения

**ProgressionSystem** (`balance.progression`):

- XP, уровни: `required_xp = floor(level_xp_base * level^1.5)`.
- Апгрейды: `max_hp`, `max_energy`, `energy_regen`, `move_speed` — уровни апгрейда и стоимость из конфига.

**SaveSystem:**

- `saves/game_save.json` — level, xp, upgrades, current_scene, best_time (legacy).
- `saves/minigame_stats.json` — массив runs: `{ time, cheater, username, mode, timestamp }`.
- Методы: top10 по режиму, leader per mode (для текста в диалоге выбора режима).

**Автосохранение:** при `switch_to` новой сцены (не main_menu), **skip на multiplayer client**.

---

## 8. BrainLink (опционально, но часть DNA проекта)

Внешнее desktop-приложение **BrainLink Client** пишет в **Windows shared memory** (`memory_name`, default `brainlink_data`).

**Чтение (управление):**

- Коды событий: `ml`, `mr`, `mu`, `md`, `stop`, `ne` (offset 13 в SHM, int32).
- **InputManager:** клавиатура **имеет приоритет** над BrainLink; ML-режим может масштабировать скорость по confidence.

**Запись (обратно в BrainLink):**

- Поля command: pending, type, event_code, timestamp.
- Отправка клавиатурных ml/mr/mu/md в history и ML; события minigame (`damage_taken`, `dodge_success`, `player_died`, `game_over`) привязывают **последнее клавиатурное** движение к ML (не prediction — anti feedback loop).

**Меню:** запуск/перезапуск клиента, пути model/history, base_fault / multi_fault, пороги confidence, чекбоксы send_*.

**Для Godot:** нужен нативный плагин/GDExtension или отдельный helper process на Windows для SHM; на других ОС — stub (только клавиатура).

---

## 9. Multiplayer (2 игрока, LAN, v1)

### 9.1. Модель

- **Host authoritative:** смена сцен, диалоги событий, **полная симуляция minigame**.
- **Client:** отправляет своё `player_state`, рисует **remote player** (интерполяция), применяет `scene_change` и **snapshots minigame**.
- **Player IDs:** `0` = host, `1` = client.
- **Transport:** TCP, одна строка JSON + `\n` на сообщение, UTF-8.
- **Port default:** `17777` (`game_config.multiplayer`).

### 9.2. Handshake

1. Client → `hello` { protocol_version: 1, player_name }.
2. Server → `welcome` { session_id, player_id: 1, host_name }.
3. После connect host may send `start_game`.
4. Host → `scene_change` для cave (и далее для всех переходов).

### 9.3. Типы сообщений

| type | Назначение |
|------|------------|
| `hello` / `welcome` / `goodbye` | Сессия |
| `start_game` | Старт (клиент закрывает меню, ждёт scene_change) |
| `player_state` | player_id, scene_id, x, z, facing, is_sitting, seq |
| `scene_change` | scene_id, spawn_x/z (host), remote_spawn_x/z (client), reason, monkey_mode (обязателен для minigame) |
| `minigame_state` | game_time, monkeys[{x,z,age}], poops[{x,z}], hp{ "0": host_hp, "1": client_hp_mirror }, game_over |
| `dialog_event` | зарезервировано (npc_id, line_index) |
| `ping` / `pong` | зарезервировано |

**Частоты (config):** player_state ~**20 Hz**, minigame_state ~**10 Hz**.

### 9.4. Spawn points (единый источник — `src/network/spawns.py`)

| scene_id | Host (0) | Client (1) |
|----------|----------|------------|
| cave | (0, 0) | (−4, 0) |
| kitchen | (12, 0) | (4, 0) |
| minigame | (0, 0) | (2, 0) |

*(При переносе сверить с актуальным файлом в репозитории — координаты могли уточняться до ±2.5 по X для minigame.)*

### 9.5. Правила коопа

- **Выходы:** проверяет host; если **remote** стоит в exit — host тоже получает transition / диалог.
- **Клиент** не вызывает локальный `switch_scene` по exit.
- **Minigame client:** не симулирует обезьян; рисует **proxy** sprites из snapshot; HP клиента — из snapshot; Top10 UI скрыт.
- **Disconnect:** возврат в main menu, сообщение `mp_disconnected`.
- **Порядок на клиенте:** применить `scene_change` **до** обработки disconnect в том же кадре (избежать гонки).

---

## 10. Конфигурация (JSON)

Скопировать семантику в Godot `ConfigFile` / Resource / JSON:

- **`config/game_config.json`** — window, player, brainlink, controls, locale, multiplayer.
- **`config/balance.json`** — minigame monkeys/poop, progression.
- **`config/locale/en.json`**, **`ru.json`** — все UI/NPC/minigame строки.
- **`config/brainlink_path.json`** — пути к BrainLink Client (опционально).

---

## 11. Ассеты (референс)

```
assets/
  fonts/segoeui.ttf          # кириллица в UI
  sprites/
    player/idle/, walk/
    npc/father.png, mother.png, mother_cook1.png, portraits/
    monkey/age1-4.png, run/, throw/
    tiles/floor.png, wall.png
    cave/cave_floor.png, cave_wall.png, cave_exit.png, cave_door.png
    kitchen/stove, fridge, microwave, counter, sink
    minigame/poop.png, clearing.png, forest.png, forest_floor.png, road.png
```

Генерация placeholder: `create_sprites.py`.

**Координаты в оригинале:** ось «вперёд» на полу — **X/Z** (Panda3D); в Godot 2D логично **X/Y**, сохранить числа, заменить Z→Y.

**Render order (эквивалент в Godot):** фон → clearing → road → лес → сущности → UI (CanvasLayer).

---

## 12. Рекомендуемая архитектура Godot

```
res/
  autoload/
    GameState.gd          # in_game, player cfg, locale
    NetworkManager.gd     # host/client, protocol encode/decode
    SaveManager.gd
    I18n.gd
    BrainLinkBridge.gd    # optional, platform-specific
  scenes/
    main_menu/
    cave/
    kitchen/
    minigame/
    ui/hud.tscn, dialog.tscn, pause.tscn
  scripts/
    player/player.gd
    npc/npc.gd
    systems/health.gd, energy.gd, progression.gd
  network/protocol.gd   # mirror MsgType + helpers
  config/                 # same JSON as original
```

- **Сцены:** одна `Node2D` root per location, `Area2D` для exits, `CharacterBody2D` или `Node2D` + manual move для игрока.
- **Minigame:** host — `Node` simulation; client — `MultiplayerSynchronizer` или custom snapshots по TCP (как сейчас).
- **Меню сети:** duplicate UX from `MainMenuScene` (host IP display, port, firewall hint on Windows).

---

## 13. MVP для Godot (приоритеты)

**P0 — паритет геймплея solo:**

- Cave ↔ Kitchen ↔ Minigame, диалоги, оба режима minigame, HP/energy/XP, HUD, pause, saves, RU/EN.

**P1 — кооп:**

- TCP protocol v1, host authority, spawns, remote player interpolation, minigame snapshots.

**P2 — BrainLink:**

- SHM read/write на Windows; без BrainLink игра полностью играбельна с клавиатуры.

**P3 — polish:**

- Top10 UI, mother cooking anim, brainlink launcher из меню, exe export.

---

## 14. Вне scope / известные ограничения оригинала

- Нет dedicated game over screen (только лог + save).
- `dialog_event` по сети не синхронизирует тексты диалогов на клиенте.
- Один клиент на хост (не lobby на N игроков).
- Звук/музыка в структуре README, но контент может отсутствовать.
- Cheater mode и dev-флаги в конфиге — для тестов.

---

## 15. Референс исходников (Python)

| Область | Файлы |
|---------|--------|
| Game loop | `src/core/game.py` |
| Scenes | `src/scenes/{cave,kitchen,minigame,main_menu}.py` |
| Network | `src/network/{protocol,server,client,controller,session,spawns}.py` |
| Entities | `src/entities/{player,remote_player,npc}.py` |
| Systems | `src/systems/{health,energy,progression}_system.py` |
| UI | `src/ui/{hud,dialog_box,pause_menu}.py` |
| BrainLink | `src/integration/brainlink.py`, `src/core/input_manager.py` |
| Saves | `src/services/save_system.py` |

---

## 16. Prompt для другого репозитория (краткая вставка)

> Реализуй игру **Get Level of Monkey** на **Godot 4 (2D top-down)** по спецификации в этом документе. Сохрани: три локации + мини-игра с двумя режимами обезьян, системы HP/энергии/XP, диалоги с отцом/мамой, цепочку запуска minigame с **отменой на хосте**, solo save/load, i18n RU/EN, LAN кооп **host authoritative** (JSON-lines TCP, scene_change + minigame snapshots). BrainLink — опциональный модуль Shared Memory под Windows. Конфиги и баланс — JSON как в оригинале. Арт — placeholder sprites из списка путей; координаты и размеры комнат/minigame взять из разделов 3–4.

---

*Версия документа: соответствует репозиторию `get_level_of_monkey` (Panda3D), ветка с multiplayer 2p. При расхождении кода и документа приоритет у актуальных `config/*.json` и `src/network/spawns.py`.*
