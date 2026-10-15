#!/usr/bin/env python3
"""Cut generated monkey sheets into idle + 2 walk frames (down, left, up)."""

from __future__ import annotations

from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "sprites" / "monkey"
SRC_DIR = Path(
    r"C:\Users\haqury\.cursor\projects\c-Users-haqury-AppData-Roaming-Godot-app-userdata-GetLevelOfAMonkey\assets"
)
DIRS = ("down", "left", "up")


def _is_magenta(r: int, g: int, b: int) -> bool:
    return r > 140 and b > 100 and g < 150 and (r + b) > g * 2 + 80


def _key(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, _a = px[x, y]
            if _is_magenta(r, g, b):
                px[x, y] = (0, 0, 0, 0)
    for _pass in range(2):
        kill: list[tuple[int, int]] = []
        w, h = im.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a < 8 or not _is_magenta(r, g, b):
                    continue
                if any(
                    nx < 0 or ny < 0 or nx >= w or ny >= h or px[nx, ny][3] < 8
                    for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                ):
                    kill.append((x, y))
        for x, y in kill:
            px[x, y] = (0, 0, 0, 0)
    return im


def _bands(counts: list[int], gap: int = 6) -> list[tuple[int, int]]:
    bands: list[tuple[int, int]] = []
    start = None
    empty = 0
    for i, n in enumerate(counts):
        if n > 8:
            if start is None:
                start = i
            empty = 0
        elif start is not None:
            empty += 1
            if empty >= gap:
                bands.append((start, i - empty + 1))
                start = None
                empty = 0
    if start is not None:
        bands.append((start, len(counts)))
    return bands


def _split_cells(im: Image.Image) -> list[list[Image.Image]]:
    w, h = im.size
    px = im.load()
    row_n = [sum(1 for x in range(w) if px[x, y][3] > 30) for y in range(h)]
    col_n = [sum(1 for y in range(h) if px[x, y][3] > 30) for x in range(w)]
    rows = _bands(row_n)
    cols = _bands(col_n)
    cells: list[list[Image.Image]] = []
    for y0, y1 in rows:
        row: list[Image.Image] = []
        for x0, x1 in cols:
            row.append(im.crop((x0, y0, x1, y1)))
        cells.append(row)
    return cells


def _bbox(im: Image.Image):
    return im.getbbox()


def _foot(im: Image.Image) -> tuple[int, int]:
    box = _bbox(im)
    if box is None:
        return im.width // 2, im.height - 1
    x0, y0, x1, y1 = box
    px = im.load()
    xs: list[int] = []
    fy = y1 - 1
    band = max(6, int((y1 - y0) * 0.22))
    for y in range(max(y0, y1 - band), y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a > 40 and r > 140 and g > 90 and b < 140:
                xs.append(x)
                fy = y
    if xs:
        return sum(xs) // len(xs), fy
    return (x0 + x1) // 2, y1 - 1


def _tight(im: Image.Image, pad: int = 2) -> Image.Image:
    box = _bbox(im)
    if box is None:
        return im
    return im.crop(
        (
            max(0, box[0] - pad),
            max(0, box[1] - pad),
            min(im.width, box[2] + pad),
            min(im.height, box[3] + pad),
        )
    )


def _pack(frames: list[Image.Image]) -> list[Image.Image]:
    frames = [_tight(f) for f in frames]
    boxes = [_bbox(f) for f in frames]
    bw = max(b[2] - b[0] for b in boxes if b)
    bh = max(b[3] - b[1] for b in boxes if b)
    cw, ch = bw + 8, bh + 8
    placed: list[Image.Image] = []
    for f in frames:
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        fx, fy = _foot(f)
        canvas.paste(f, (cw // 2 - fx, ch - 3 - fy), f)
        placed.append(canvas)
    return placed


def _export_age(age: int, sheet_path: Path) -> None:
    im = _key(Image.open(sheet_path))
    grid = _split_cells(im)
    if len(grid) < 3 or any(len(row) < 3 for row in grid[:3]):
        raise SystemExit(f"age {age}: expected a grid, got {len(grid)} rows")
    idle_row = grid[0]
    walk_a = grid[1]
    walk_b = grid[2]
    dest = OUT / f"age{age}"
    dest.mkdir(parents=True, exist_ok=True)
    for col, name in enumerate(DIRS):
        packed = _pack([idle_row[col], walk_a[col], walk_b[col]])
        packed[0].save(dest / f"{name}_idle.png")
        packed[1].save(dest / f"{name}_1.png")
        packed[2].save(dest / f"{name}_2.png")
    # Front idle also fills the legacy single-file path.
    _pack([idle_row[0]])[0].save(OUT / f"age{age}.png")
    print(f"age {age}: {len(grid)} rows x {len(grid[0])} cols -> {dest}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for age in range(1, 5):
        src = SRC_DIR / f"monkey_age{age}_sheet.jpg"
        if not src.exists():
            src = SRC_DIR / f"monkey_age{age}_sheet.png"
        _export_age(age, src)
    print("monkey sprites ready")


if __name__ == "__main__":
    main()
