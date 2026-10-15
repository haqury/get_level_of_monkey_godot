#!/usr/bin/env python3
"""
Rebuild player sprites from the RO sheet.

- Transparent background (checkerboard keyed from the edges)
- Halo removed (floating ring is not part of the body)
- Directions: down, left, right, up. Right walk-step A on the sheet faces left and is flipped.
- 5 walk frames per direction from the two real steps (1,1,2,2,1)
- New master: assets/sprites/player/source_spritesheet.png
"""

from __future__ import annotations

import shutil
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / "assets" / "sprites" / "player"
SHEET_JPG = PLAYER / "source_spritesheet.jpg"
SHEET_ORIG = PLAYER / "source_spritesheet_original.jpg"
SHEET_OUT = PLAYER / "source_spritesheet.png"
OUT_IDLE = PLAYER / "idle"
OUT_WALK = PLAYER / "walk"

DIRS = ["down", "left", "right", "up"]
COLS, ROWS = 4, 3
WALK_FRAMES = 5
WALK_PATTERN = (0, 0, 1, 1, 0)


def _is_checker(r: int, g: int, b: int) -> bool:
    spread = max(r, g, b) - min(r, g, b)
    avg = (r + g + b) / 3.0
    return spread <= 18 and avg >= 208


def _key_checker(im: Image.Image) -> Image.Image:
    """Flood-fill the light checkerboard from the cell edges. Coat stays inside the outline."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        r, g, b, _a = px[x, y]
        if not _is_checker(r, g, b):
            continue
        px[x, y] = (0, 0, 0, 0)
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))
    return im


def _nibble_fringe(im: Image.Image, passes: int = 2) -> None:
    """Drop jpeg fringe pixels that sit on the transparent edge and look like background."""
    w, h = im.size
    px = im.load()
    for _ in range(passes):
        kill: list[tuple[int, int]] = []
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a < 8 or not _is_checker(r, g, b):
                    continue
                edge = False
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if nx < 0 or ny < 0 or nx >= w or ny >= h or px[nx, ny][3] < 8:
                        edge = True
                        break
                if edge:
                    kill.append((x, y))
        for x, y in kill:
            px[x, y] = (0, 0, 0, 0)


def _keep_body(im: Image.Image) -> None:
    """Keep the largest opaque blob (the character). Halo and loose shadow go away."""
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    best: list[tuple[int, int]] = []
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if seen[i] or px[x, y][3] < 40:
                continue
            blob: list[tuple[int, int]] = []
            q: deque[tuple[int, int]] = deque([(x, y)])
            seen[i] = 1
            while q:
                cx, cy = q.popleft()
                blob.append((cx, cy))
                for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        continue
                    ni = ny * w + nx
                    if seen[ni] or px[nx, ny][3] < 40:
                        continue
                    seen[ni] = 1
                    q.append((nx, ny))
            if len(blob) > len(best):
                best = blob
    keep = set(best)
    for y in range(h):
        for x in range(w):
            if (x, y) not in keep:
                px[x, y] = (0, 0, 0, 0)


def _is_boot(r: int, g: int, b: int) -> bool:
    avg = (r + g + b) / 3.0
    if avg > 115 or (r > 140 and g > 90):
        return False
    spread = max(r, g, b) - min(r, g, b)
    return r > 50 and g > 20 and b < 80 and spread > 16


def _is_shadow(r: int, g: int, b: int) -> bool:
    spread = max(r, g, b) - min(r, g, b)
    avg = (r + g + b) / 3.0
    gray = spread <= 28 and 90 <= avg <= 190
    gold = r > 150 and g > 110 and b < 120 and r >= g
    return gray or gold


def _bbox(im: Image.Image) -> tuple[int, int, int, int] | None:
    return im.getbbox()


def _foot(im: Image.Image) -> tuple[int, int]:
    box = _bbox(im)
    if box is None:
        return im.width // 2, im.height - 1
    x0, y0, x1, y1 = box
    px = im.load()
    w, h = im.size
    band = max(12, int((y1 - y0) * 0.18))
    xs: list[int] = []
    fy = y0
    for y in range(max(y0, y1 - band), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            r, g, b, a = px[x, y]
            if a > 40 and _is_boot(r, g, b):
                xs.append(x)
                fy = max(fy, y)
    if xs:
        return sum(xs) // len(xs), fy
    return (x0 + x1) // 2, y1 - 1


def _strip_halo(im: Image.Image) -> None:
    """Cut the floating ring: it sits above a thin gap, the hair starts under that gap."""
    box = _bbox(im)
    if box is None:
        return
    _x0, y0, _x1, y1 = box
    px = im.load()
    w, h = im.size
    counts = [sum(1 for x in range(w) if px[x, y][3] > 40) for y in range(h)]
    span = max(1, y1 - y0)
    limit = min(h, y0 + int(span * 0.42))
    peak = 0
    gap: int | None = None
    for y in range(y0, limit):
        peak = max(peak, counts[y])
        if peak >= 24 and counts[y] <= max(18, int(peak * 0.55)):
            if gap is None or counts[y] < counts[gap]:
                gap = y
    if gap is None or gap + 8 >= h:
        return
    below = max(counts[y] for y in range(gap + 1, min(h, gap + 16)))
    if below < peak * 0.45:
        return
    for y in range(gap + 1):
        for x in range(w):
            px[x, y] = (0, 0, 0, 0)


def _strip_floor(im: Image.Image) -> None:
    px = im.load()
    w, h = im.size
    box = _bbox(im)
    if box is None:
        return
    x0, _y0, x1, _y1 = box
    _, fy = _foot(im)
    for y in range(fy + 1, h):
        for x in range(w):
            px[x, y] = (0, 0, 0, 0)
    half = max(16, int((x1 - x0) * 0.7))
    cx = (x0 + x1) // 2
    for y in range(max(0, fy - 10), fy + 1):
        for x in range(max(0, cx - half), min(w, cx + half)):
            r, g, b, a = px[x, y]
            if a < 8 or _is_boot(r, g, b):
                continue
            if _is_shadow(r, g, b):
                px[x, y] = (0, 0, 0, 0)


def _process_cell(raw: Image.Image) -> Image.Image:
    im = _key_checker(raw)
    _nibble_fringe(im)
    _keep_body(im)
    _strip_halo(im)
    _strip_floor(im)
    _keep_body(im)
    box = _bbox(im)
    if box is None:
        return im
    pad = 2
    return im.crop(
        (
            max(0, box[0] - pad),
            max(0, box[1] - pad),
            min(im.width, box[2] + pad),
            min(im.height, box[3] + pad),
        )
    )


def _should_flip_right(row: int) -> bool:
    # Sheet column "right": idle and walk-step B already face right.
    # Walk-step A (middle row) faces left.
    return row == 1


def _place(im: Image.Image, cw: int, ch: int) -> Image.Image:
    slot = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    fx, fy = _foot(im)
    slot.paste(im, (cw // 2 - fx, ch - 4 - fy), im)
    return slot


def _uniform(frames: list[Image.Image]) -> list[Image.Image]:
    boxes = [_bbox(f) for f in frames]
    body_w = max((b[2] - b[0]) for b in boxes if b)
    body_h = max((b[3] - b[1]) for b in boxes if b)
    cw = body_w + 16
    ch = body_h + 12
    placed = [_place(f, cw, ch) for f in frames]
    union = _bbox(placed[0])
    assert union is not None
    for p in placed[1:]:
        b = _bbox(p)
        if b is None:
            continue
        union = (min(union[0], b[0]), min(union[1], b[1]), max(union[2], b[2]), max(union[3], b[3]))
    out_w = union[2] - union[0] + 4
    out_h = union[3] - union[1] + 4
    out: list[Image.Image] = []
    for p in placed:
        fx, fy = _foot(p)
        canvas = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
        canvas.paste(p, (out_w // 2 - fx, out_h - 2 - fy), p)
        out.append(canvas)
    return out


def _source_sheet() -> Path:
    if SHEET_ORIG.exists():
        return SHEET_ORIG
    if SHEET_JPG.exists():
        return SHEET_JPG
    raise SystemExit(f"Missing {SHEET_JPG}")


def main() -> None:
    src = _source_sheet()
    if not SHEET_ORIG.exists() and src == SHEET_JPG:
        shutil.copy2(SHEET_JPG, SHEET_ORIG)

    sheet = Image.open(src)
    cw, ch = sheet.width // COLS, sheet.height // ROWS

    cells: list[list[Image.Image]] = []
    for col in range(COLS):
        col_cells: list[Image.Image] = []
        for row in range(ROWS):
            raw = sheet.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
            if DIRS[col] == "right" and _should_flip_right(row):
                raw = raw.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            col_cells.append(_process_cell(raw))
        cells.append(col_cells)

    # Left walk-step A on the sheet still has the halo. Mirror the cleaned right step.
    left_i = DIRS.index("left")
    right_i = DIRS.index("right")
    cells[left_i][1] = cells[right_i][1].transpose(Image.Transpose.FLIP_LEFT_RIGHT)

    # Master sheet: 4 directions x (idle + 5 walk frames), transparent.
    masters: list[list[Image.Image]] = []
    for col in range(COLS):
        idle, step_a, step_b = cells[col]
        pair = (step_a, step_b)
        walk = [pair[WALK_PATTERN[i]].copy() for i in range(WALK_FRAMES)]
        masters.append(_uniform([idle] + walk))

    cell_w = max(f.width for col in masters for f in col)
    cell_h = max(f.height for col in masters for f in col)
    grid = Image.new("RGBA", (cell_w * COLS, cell_h * (1 + WALK_FRAMES)), (0, 0, 0, 0))
    for col, frames in enumerate(masters):
        for row, frame in enumerate(frames):
            fx, fy = _foot(frame)
            slot = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
            slot.paste(frame, (cell_w // 2 - fx, cell_h - 4 - fy), frame)
            grid.paste(slot, (col * cell_w, row * cell_h))
    grid.save(SHEET_OUT)

    OUT_IDLE.mkdir(parents=True, exist_ok=True)
    OUT_WALK.mkdir(parents=True, exist_ok=True)
    for col, name in enumerate(DIRS):
        frames = masters[col]
        frames[0].save(OUT_IDLE / f"{name}.png")
        frames[0].save(PLAYER / "base_down.png") if name == "down" else None
        for i in range(WALK_FRAMES):
            frames[i + 1].save(OUT_WALK / f"{name}_{i + 1}.png")

    print(f"Source {src.name} -> {SHEET_OUT.name} ({COLS} dirs x idle+{WALK_FRAMES} walk, transparent, no halo)")


if __name__ == "__main__":
    main()
