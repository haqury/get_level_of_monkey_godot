#!/usr/bin/env python3
"""Split RO-style player sheet: idle + 5-frame walk cycles (shadow stripped)."""

from __future__ import annotations

from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
SHEET = ROOT / "assets" / "sprites" / "player" / "source_spritesheet.jpg"
OUT_IDLE = ROOT / "assets" / "sprites" / "player" / "idle"
OUT_WALK = ROOT / "assets" / "sprites" / "player" / "walk"

DIRS = ["down", "left", "right", "up"]
WALK_FRAMES = 5


def _key_bg(img: Image.Image) -> tuple[int, int, int]:
    px = img.load()
    corners = [px[0, 0], px[img.width - 1, 0], px[0, img.height - 1], px[img.width - 1, img.height - 1]]
    return tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))


def _transparent_bg(cell: Image.Image, tol: int = 28) -> Image.Image:
    cell = cell.convert("RGBA")
    bg = _key_bg(cell)
    px = cell.load()
    for y in range(cell.height):
        for x in range(cell.width):
            r, g, b, a = px[x, y]
            if abs(r - bg[0]) <= tol and abs(g - bg[1]) <= tol and abs(b - bg[2]) <= tol:
                px[x, y] = (r, g, b, 0)
    return cell


def _row_shadow_ratio(px, w: int, y: int) -> float:
    opaque = 0
    shadow_like = 0
    for x in range(w):
        r, g, b, a = px[x, y]
        if a < 8:
            continue
        opaque += 1
        spread = max(r, g, b) - min(r, g, b)
        avg = (r + g + b) / 3.0
        if spread <= 42 and (avg >= 125 or avg <= 105):
            shadow_like += 1
    if opaque == 0:
        return 0.0
    return shadow_like / opaque


def _foot_anchor(im: Image.Image) -> tuple[int, int]:
    bbox = _content_bbox(im)
    px = im.load()
    w, h = im.size
    x0, y0, x1, y1 = bbox
    x1 = min(x1, w)
    y1 = min(y1, h)
    band = max(8, int((y1 - y0) * 0.14))
    boot_xs: list[int] = []
    boot_y = -1
    for y in range(max(y0, y1 - band), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            r, g, b, a = px[x, y]
            if a > 40 and _is_boot_pixel(r, g, b):
                boot_xs.append(x)
                boot_y = max(boot_y, y)
    if boot_y >= 0:
        return sum(boot_xs) // len(boot_xs), boot_y

    xs: list[int] = []
    foot_y = y1 - 1
    for y in range(max(y0, y1 - band), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            if px[x, y][3] > 40:
                r, g, b, _a = px[x, y]
                spread = max(r, g, b) - min(r, g, b)
                avg = (r + g + b) / 3.0
                if (r > 95 and g > 65 and b < 130 and spread < 95 and avg > 100) or (
                    r > 145 and g > 95 and b < 135 and r >= g >= b
                ):
                    continue
                xs.append(x)
                foot_y = max(foot_y, y)
    foot_cx = sum(xs) // len(xs) if xs else (x0 + x1) // 2
    return foot_cx, foot_y


def _is_boot_pixel(r: int, g: int, b: int) -> bool:
    spread = max(r, g, b) - min(r, g, b)
    avg = (r + g + b) / 3.0
    # RO floor oval is bright gold; real boots are dark brown/black.
    if avg > 112 or (r > 130 and g > 75):
        return False
    return r > 55 and g > 25 and b < 70 and spread > 18


def _is_bright_gold(r: int, g: int, b: int) -> bool:
    return r > 118 and g > 78 and b < 145 and r >= g >= b


def _strip_ground_debris(cell: Image.Image) -> Image.Image:
    """Remove gray/golden ground shadows and stray pixels under boots."""
    cell = cell.convert("RGBA")
    px = cell.load()
    w, h = cell.size
    bbox = _content_bbox(cell)
    if not bbox:
        return cell
    x0, y0, x1, y1 = bbox
    _, foot_y = _foot_anchor(cell)

    for y in range(foot_y + 1, h):
        for x in range(w):
            px[x, y] = (0, 0, 0, 0)

    cx = (x0 + x1) // 2
    half_w = max(10, int((x1 - x0) * 0.7))
    def _is_ground_artifact(r: int, g: int, b: int) -> bool:
        if _is_bright_gold(r, g, b):
            return True
        spread = max(r, g, b) - min(r, g, b)
        avg = (r + g + b) / 3.0
        golden_smear = r > 95 and g > 65 and b < 130 and spread < 95
        gray_shadow = spread <= 48 and (avg >= 118 or avg <= 108)
        return golden_smear or gray_shadow

    for y in range(max(y0, foot_y - 14), foot_y + 1):
        for x in range(max(0, cx - half_w), min(w, cx + half_w)):
            r, g, b, a = px[x, y]
            if a < 8 or _is_boot_pixel(r, g, b):
                continue
            if _is_ground_artifact(r, g, b):
                px[x, y] = (0, 0, 0, 0)

    for y in range(max(y0, foot_y - 8), min(h, foot_y + 8)):
        for x in range(max(0, x0), min(w, x1)):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            if _is_bright_gold(r, g, b):
                px[x, y] = (0, 0, 0, 0)

    y_cut = h
    while y_cut > foot_y + 1 and _row_shadow_ratio(px, w, y_cut - 1) >= 0.35:
        y_cut -= 1
    if y_cut < h:
        cell = cell.crop((0, 0, w, y_cut))
    return cell


def _remove_shadow(cell: Image.Image) -> Image.Image:
    cell = _strip_ground_debris(cell)
    return cell


def _crop_content(cell: Image.Image, pad: int = 6) -> Image.Image:
    bbox = cell.getbbox()
    if not bbox:
        return cell
    x0 = max(0, bbox[0] - pad)
    y0 = max(0, bbox[1] - pad)
    x1 = min(cell.width, bbox[2] + pad)
    y1 = min(cell.height, bbox[3] + pad)
    return cell.crop((x0, y0, x1, y1))


def _process_cell(raw: Image.Image, *, walk_step_a: bool = False) -> Image.Image:
    cell = _transparent_bg(raw)
    cell = _remove_shadow(cell)
    if walk_step_a:
        cell = _strip_walk_a_floor(cell)
    return _crop_content(cell, pad=4)


def _strip_walk_a_floor(cell: Image.Image) -> Image.Image:
    """Sheet walk row 1 keeps a gold oval under the feet; row 2 does not."""
    cell = cell.convert("RGBA")
    px = cell.load()
    w, h = cell.size
    bbox = _content_bbox(cell)
    if not bbox:
        return cell
    x0, y0, x1, y1 = bbox
    _, foot_y = _foot_anchor(cell)
    for y in range(max(y0, foot_y - 2), min(h, y1 + 1)):
        for x in range(max(0, x0), min(w, x1)):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            if _is_bright_gold(r, g, b) or (_is_ground_artifact_row(r, g, b) and not _is_boot_pixel(r, g, b)):
                px[x, y] = (0, 0, 0, 0)
    for y in range(foot_y + 1, h):
        for x in range(w):
            px[x, y] = (0, 0, 0, 0)
    return cell


def _is_ground_artifact_row(r: int, g: int, b: int) -> bool:
    spread = max(r, g, b) - min(r, g, b)
    avg = (r + g + b) / 3.0
    return _is_bright_gold(r, g, b) or (spread <= 48 and (avg >= 118 or avg <= 108))


def _finalize_frame(im: Image.Image, pad: int = 3) -> Image.Image:
    im = _strip_ground_debris(im)
    bbox = im.getbbox()
    if not bbox:
        return im
    x0, y0, x1, y1 = bbox
    return im.crop(
        (
            max(0, x0 - pad),
            max(0, y0 - pad),
            min(im.width, x1 + pad),
            min(im.height, y1 + pad),
        )
    )


def _content_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    return im.getbbox() or (0, 0, im.width, im.height)


def _canvas_for_frames(*images: Image.Image, pad_bottom: int = 4, pad_top: int = 8, pad_x: int = 10) -> tuple[int, int]:
    bboxes = [_content_bbox(im) for im in images]
    body_w = max(b[2] - b[0] for b in bboxes)
    body_h = max(b[3] - b[1] for b in bboxes)
    return body_w + pad_x * 2, body_h + pad_top + pad_bottom


def _place_on_canvas(im: Image.Image, canvas_w: int, canvas_h: int, pad_bottom: int = 4) -> Image.Image:
    """Align foot center to canvas center; shared baseline."""
    out = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    foot_cx, foot_y = _foot_anchor(im)
    px = canvas_w // 2 - foot_cx
    py = canvas_h - pad_bottom - foot_y
    out.paste(im, (px, py), im)
    return out


def _uniform_pack(frames: list[Image.Image], pad_bottom: int = 4, tight_crop: bool = False) -> list[Image.Image]:
    """Same export size; feet on one baseline, foot center horizontally centered."""
    if not frames:
        return []
    pad_side = 10
    pad_top = 8
    cleaned = [_strip_ground_debris(f) for f in frames]
    bboxes = [_content_bbox(f) for f in cleaned]
    body_w = max(b[2] - b[0] for b in bboxes)
    body_h = max(b[3] - b[1] for b in bboxes)
    canvas_w = body_w + pad_side * 2
    canvas_h = body_h + pad_top + pad_bottom
    placed = [_place_on_canvas(f, canvas_w, canvas_h, pad_bottom) for f in cleaned]
    union = _content_bbox(placed[0])
    for p in placed[1:]:
        b = _content_bbox(p)
        union = (
            min(union[0], b[0]),
            min(union[1], b[1]),
            max(union[2], b[2]),
            max(union[3], b[3]),
        )
    pad = 3
    out_w = union[2] - union[0] + pad * 2
    out_h = union[3] - union[1] + pad * 2
    packed: list[Image.Image] = []
    for p in placed:
        foot_cx, foot_y = _foot_anchor(p)
        out = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
        px = out_w // 2 - foot_cx
        py = out_h - pad - foot_y
        out.paste(p, (px, py), p)
        packed.append(_finalize_frame(out) if tight_crop else out)
    return packed


def _align_direction(idle: Image.Image, w1: Image.Image, w2: Image.Image) -> tuple[Image.Image, Image.Image, Image.Image]:
    packed = _uniform_pack([idle, w1, w2], tight_crop=True)
    return packed[0], packed[1], packed[2]


def _orient_right_row(cell: Image.Image, walk_row: int) -> Image.Image:
    ## Row 1 (step A) faces left on sheet; row 2 (step B) already faces right.
    if walk_row == 1:
        return cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return cell


# Two sheet walk rows → five crisp frames (no cross-fade).
_WALK_KEY_INDEX = (0, 0, 1, 1, 0)


def _walk_cycle_frame(w1: Image.Image, w2: Image.Image, index: int) -> Image.Image:
    pair = (w1, w2)
    key = _WALK_KEY_INDEX[index % len(_WALK_KEY_INDEX)]
    return pair[key].copy()


def main() -> None:
    src = SHEET
    if not src.exists():
        alt = Path(
            r"C:\Users\haqury\.cursor\projects\c-Users-haqury-AppData-Roaming-Godot-app-userdata-GetLevelOfAMonkey\assets\player_ro_spritesheet.jpg"
        )
        if alt.exists():
            src.parent.mkdir(parents=True, exist_ok=True)
            src.write_bytes(alt.read_bytes())
        else:
            raise SystemExit(f"Missing spritesheet: {SHEET}")

    sheet = Image.open(src)
    cols, rows = 4, 3
    cw, ch = sheet.width // cols, sheet.height // rows
    OUT_IDLE.mkdir(parents=True, exist_ok=True)
    OUT_WALK.mkdir(parents=True, exist_ok=True)

    for old in OUT_WALK.glob("*.png"):
        try:
            old.unlink()
        except OSError:
            pass

    raw_rows: dict[str, list[Image.Image]] = {d: [] for d in DIRS}
    for row in range(rows):
        for col in range(cols):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            raw_rows[DIRS[col]].append(sheet.crop(box))

    for name in DIRS:
        proc = [_process_cell(raw_rows[name][row], walk_step_a=(row == 1)) for row in range(rows)]
        if name == "right":
            proc[0] = proc[0].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            proc[1] = _orient_right_row(proc[1], 1)
            proc[2] = _orient_right_row(proc[2], 2)
        idle, w1, w2 = _align_direction(proc[0], proc[1], proc[2])
        idle.save(OUT_IDLE / f"{name}.png")
        walk_raw = [_walk_cycle_frame(w1, w2, i) for i in range(WALK_FRAMES)]
        for i, frame in enumerate(_uniform_pack(walk_raw, tight_crop=False)):
            frame.save(OUT_WALK / f"{name}_{i + 1}.png")

    print(f"Split {src.name} -> {cw}x{ch} cells, {WALK_FRAMES} walk frames per dir (no shadow)")


if __name__ == "__main__":
    main()
