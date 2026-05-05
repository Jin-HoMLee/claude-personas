"""Annotate claude-personas hero image with role badges, bidirectional connection lines,
and a hero title. Run from anywhere: `python3 scripts/annotate_hero.py`.

Requires: pip install pillow pilmoji
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from pilmoji.source import GoogleEmojiSource
from pathlib import Path
import math

REPO_ROOT = Path(__file__).resolve().parent.parent
SRC = str(REPO_ROOT / "assets" / "mac-vscode-personas-overview.png")
DST = str(REPO_ROOT / "assets" / "mac-vscode-personas-overview-annotated.png")

WINDOWS = {
    "cerebrum":  {"emoji": "🧠", "text": "Cerebrum",  "color": (45, 212, 191)},
    "scientist": {"emoji": "🔬", "text": "Scientist", "color": (59, 130, 246)},
    "developer": {"emoji": "💻", "text": "Developer", "color": (107, 114, 128)},
    "pm":        {"emoji": "📋", "text": "PM",        "color": (217, 70, 239)},
}

BADGE_POS = {
    "cerebrum":  (60, 60),
    "scientist": (1460, 60),
    "developer": (60, 640),
    "pm":        (1460, 640),
}

SUBTITLES = {
    "cerebrum":  "(claude-personas prototype)",
    "scientist": "(or Designer / your variant)",
}

TITLE_TEXT = "claude-personas"
TITLE_TAGLINE = "a multi-role memory hub for Claude Code"
TITLE_FONT_SIZE = 96
TAGLINE_FONT_SIZE = 44
HEADER_HEIGHT = 320
HEADER_BG = (8, 12, 24)  # near-black, picks up the wallpaper's deep-navy tone

LINE_WIDTH = 4
LINE_ALPHA = 200
ARROW_SIZE = 26
BADGE_FONT_SIZE = 56
BADGE_PADDING_X = 32
BADGE_PADDING_Y = 22
EMOJI_SIZE = 56
EMOJI_TEXT_GAP = 14
SHADOW_OFFSET = 6
SHADOW_BLUR = 8
SHADOW_ALPHA = 110
SUBTITLE_FONT_SIZE = 34
SUBTITLE_GAP = 14
SUBTITLE_STROKE_WIDTH = 3


def load_font(size):
    for path in [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def load_bold_font(size):
    candidates = [
        ("/System/Library/Fonts/Helvetica.ttc", 1),
        ("/System/Library/Fonts/HelveticaNeue.ttc", 2),
        ("/System/Library/Fonts/HelveticaNeue.ttc", 1),
        ("/Library/Fonts/Arial Bold.ttf", 0),
        ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0),
    ]
    for path, idx in candidates:
        try:
            return ImageFont.truetype(path, size, index=idx)
        except (OSError, IndexError):
            continue
    return load_font(size)


def get_emoji_image(emoji_char, size):
    source = GoogleEmojiSource()
    stream = source.get_emoji(emoji_char)
    img = Image.open(stream).convert("RGBA")
    return img.resize((size, size), Image.LANCZOS)


def badge_size(role, font):
    text_bbox = font.getbbox(WINDOWS[role]["text"])
    text_w = text_bbox[2] - text_bbox[0]
    visible_text_h = text_bbox[3] - text_bbox[1]
    inner_h = max(EMOJI_SIZE, visible_text_h)
    inner_w = EMOJI_SIZE + EMOJI_TEXT_GAP + text_w
    return inner_w + 2 * BADGE_PADDING_X, inner_h + 2 * BADGE_PADDING_Y


def badge_anchor(role, font, side):
    x, y = BADGE_POS[role]
    w, h = badge_size(role, font)
    if side == "right":       return (x + w, y + h // 2)
    if side == "left":        return (x, y + h // 2)
    if side == "top":         return (x + w // 2, y)
    if side == "bottom":      return (x + w // 2, y + h)
    if side == "topright":    return (x + w, y)
    if side == "bottomright": return (x + w, y + h)
    if side == "topleft":     return (x, y)
    if side == "bottomleft":  return (x, y + h)
    raise ValueError(side)


def draw_arrow_head(draw, tip, dir_angle, color, size):
    head = math.radians(28)
    x1 = tip[0] - size * math.cos(dir_angle - head)
    y1 = tip[1] - size * math.sin(dir_angle - head)
    x2 = tip[0] - size * math.cos(dir_angle + head)
    y2 = tip[1] - size * math.sin(dir_angle + head)
    draw.polygon([tip, (x1, y1), (x2, y2)], fill=color)


def draw_straight(draw, p1, p2, color, width, arrow_size):
    draw.line([p1, p2], fill=color, width=width)
    angle = math.atan2(p2[1] - p1[1], p2[0] - p1[0])
    draw_arrow_head(draw, p2, angle, color, arrow_size)
    draw_arrow_head(draw, p1, angle + math.pi, color, arrow_size)


def quadratic_bezier(p0, p1, p2, n=80):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    return pts


def draw_curve(draw, p0, p2, control, color, width, arrow_size):
    pts = quadratic_bezier(p0, control, p2)
    for i in range(len(pts) - 1):
        draw.line([pts[i], pts[i + 1]], fill=color, width=width)
    angle_end = math.atan2(pts[-1][1] - pts[-2][1], pts[-1][0] - pts[-2][0])
    angle_start = math.atan2(pts[1][1] - pts[0][1], pts[1][0] - pts[0][0]) + math.pi
    draw_arrow_head(draw, pts[-1], angle_end, color, arrow_size)
    draw_arrow_head(draw, pts[0], angle_start, color, arrow_size)


def render_shadow(size, role, font):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = BADGE_POS[role]
    w, h = badge_size(role, font)
    radius = h // 2
    d.rounded_rectangle(
        [x + SHADOW_OFFSET, y + SHADOW_OFFSET, x + w + SHADOW_OFFSET, y + h + SHADOW_OFFSET],
        radius=radius,
        fill=(0, 0, 0, SHADOW_ALPHA),
    )
    return layer.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))


def main():
    base = Image.open(SRC).convert("RGBA")
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    font = load_font(BADGE_FONT_SIZE)

    line_color = WINDOWS["cerebrum"]["color"] + (LINE_ALPHA,)

    # Cerebrum -> Scientist : horizontal at badge mid-y
    p_cs1 = badge_anchor("cerebrum", font, "right")
    p_cs2 = badge_anchor("scientist", font, "left")
    draw_straight(draw, p_cs1, p_cs2, line_color, LINE_WIDTH, ARROW_SIZE)

    # Cerebrum -> Developer : vertical
    p_cd1 = badge_anchor("cerebrum", font, "bottom")
    p_cd2 = badge_anchor("developer", font, "top")
    draw_straight(draw, p_cd1, p_cd2, line_color, LINE_WIDTH, ARROW_SIZE)

    # Cerebrum -> PM : Bezier curve, BOWING DOWN to stay strictly below the Scientist line.
    # Endpoints are bottom-right of cerebrum + top-left of PM (both already below the horizontal line).
    p_cp1 = badge_anchor("cerebrum", font, "bottomright")
    p_cp2 = badge_anchor("pm", font, "topleft")
    midx = (p_cp1[0] + p_cp2[0]) / 2
    midy = (p_cp1[1] + p_cp2[1]) / 2
    control = (midx, midy + 220)
    draw_curve(draw, p_cp1, p_cp2, control, line_color, LINE_WIDTH, ARROW_SIZE)

    # Drop shadows
    shadow_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    for role in WINDOWS:
        shadow_layer = Image.alpha_composite(shadow_layer, render_shadow(base.size, role, font))

    # Badge bodies
    for role in WINDOWS:
        x, y = BADGE_POS[role]
        w, h = badge_size(role, font)
        color = WINDOWS[role]["color"]
        radius = h // 2
        draw.rounded_rectangle([x, y, x + w, y + h], radius=radius, fill=color + (240,))

    composite = Image.alpha_composite(base, shadow_layer)
    composite = Image.alpha_composite(composite, overlay)

    # Render emoji and text manually for precise alignment
    text_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    text_draw = ImageDraw.Draw(text_layer)
    for role, info in WINDOWS.items():
        x, y = BADGE_POS[role]
        w, h = badge_size(role, font)
        text = info["text"]
        text_bbox = font.getbbox(text)
        text_w = text_bbox[2] - text_bbox[0]
        visible_text_h = text_bbox[3] - text_bbox[1]

        inner_w = EMOJI_SIZE + EMOJI_TEXT_GAP + text_w
        inner_x_start = x + (w - inner_w) // 2

        emoji_img = get_emoji_image(info["emoji"], EMOJI_SIZE)
        emoji_y = y + (h - EMOJI_SIZE) // 2
        text_layer.paste(emoji_img, (inner_x_start, emoji_y), emoji_img)

        # Text: center the *visible* glyphs by subtracting bbox.top offset
        text_x = inner_x_start + EMOJI_SIZE + EMOJI_TEXT_GAP - text_bbox[0]
        text_y = y + (h - visible_text_h) // 2 - text_bbox[1]
        text_draw.text((text_x, text_y), text, fill=(255, 255, 255, 255), font=font)

    composite = Image.alpha_composite(composite, text_layer)

    # Subtitles below specific badges — dark pill background for legibility over VSCode content
    subtitle_font = load_font(SUBTITLE_FONT_SIZE)
    subtitle_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    subtitle_draw = ImageDraw.Draw(subtitle_layer)
    SUB_PAD_X = 16
    SUB_PAD_Y = 8
    for role, caption in SUBTITLES.items():
        x, y = BADGE_POS[role]
        w, h = badge_size(role, font)
        bbox = subtitle_font.getbbox(caption)
        cap_w = bbox[2] - bbox[0]
        cap_h = bbox[3] - bbox[1]
        pill_w = cap_w + 2 * SUB_PAD_X
        pill_h = cap_h + 2 * SUB_PAD_Y
        pill_x = x + (w - pill_w) // 2
        pill_y = y + h + SUBTITLE_GAP
        subtitle_draw.rounded_rectangle(
            [pill_x, pill_y, pill_x + pill_w, pill_y + pill_h],
            radius=pill_h // 2,
            fill=(0, 0, 0, 180),
        )
        cap_x = pill_x + SUB_PAD_X - bbox[0]
        cap_y = pill_y + SUB_PAD_Y - bbox[1]
        subtitle_draw.text(
            (cap_x, cap_y), caption,
            fill=(255, 255, 255, 255),
            font=subtitle_font,
        )
    composite = Image.alpha_composite(composite, subtitle_layer)

    # Extend canvas with a dark header strip; render hero title + tagline
    extended = Image.new("RGBA", (composite.width, composite.height + HEADER_HEIGHT), HEADER_BG + (255,))
    extended.paste(composite, (0, HEADER_HEIGHT))

    title_font = load_bold_font(TITLE_FONT_SIZE)
    tagline_font = load_font(TAGLINE_FONT_SIZE)
    cerebrum_color = WINDOWS["cerebrum"]["color"]

    title_bbox = title_font.getbbox(TITLE_TEXT)
    title_w = title_bbox[2] - title_bbox[0]
    title_h = title_bbox[3] - title_bbox[1]
    tagline_bbox = tagline_font.getbbox(TITLE_TAGLINE)
    tagline_w = tagline_bbox[2] - tagline_bbox[0]
    tagline_h = tagline_bbox[3] - tagline_bbox[1]

    GAP = 48
    block_h = title_h + GAP + tagline_h
    block_top = (HEADER_HEIGHT - block_h) // 2

    title_layer = Image.new("RGBA", extended.size, (0, 0, 0, 0))
    title_draw = ImageDraw.Draw(title_layer)

    # Title — large bold white, with a colored underline accent to tie to cerebrum
    title_x = (extended.width - title_w) // 2 - title_bbox[0]
    title_y = block_top - title_bbox[1]
    title_draw.text((title_x, title_y), TITLE_TEXT, fill=(255, 255, 255, 255), font=title_font)

    # Accent bar (turquoise) just below the title — extends well beyond the tagline
    # so it reads as a divider element rather than a tight underline
    accent_w = tagline_w + 240
    accent_x = (extended.width - accent_w) // 2
    accent_y = block_top + title_h + (GAP // 2) - 2
    title_draw.rounded_rectangle(
        [accent_x, accent_y, accent_x + accent_w, accent_y + 5],
        radius=3,
        fill=cerebrum_color + (255,),
    )

    # Tagline — smaller, lighter
    tagline_x = (extended.width - tagline_w) // 2 - tagline_bbox[0]
    tagline_y = block_top + title_h + GAP - tagline_bbox[1]
    title_draw.text((tagline_x, tagline_y), TITLE_TAGLINE, fill=(200, 210, 220, 255), font=tagline_font)

    extended = Image.alpha_composite(extended, title_layer)
    extended.convert("RGB").save(DST, "PNG", optimize=True)
    print(f"Wrote: {DST}")


if __name__ == "__main__":
    main()
