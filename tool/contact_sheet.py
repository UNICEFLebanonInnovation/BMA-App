#!/usr/bin/env python3
"""Assemble screenshots/contact_sheet.png from the phone captures.

Run after regenerating the screenshots:

    BMA_SCREENSHOTS=1 flutter test test/screenshots/screenshot_generator_test.dart
    python3 tool/contact_sheet.py

Needs Pillow. Tablet captures (``*_tablet.png``) are left out: the sheet keeps
one aspect ratio so the thumbnails line up.
"""

import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 412, 915
COLUMNS = 5
PAD, CAPTION = 24, 34
BACKGROUND = (244, 247, 246)
BORDER = (200, 205, 210)
LABEL = (0, 51, 102)
FONT = '/home/user/tools/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf'


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    paths = sorted(
        p for p in glob.glob(os.path.join(root, 'screenshots', '[0-9][0-9]_*.png'))
        if '_tablet' not in os.path.basename(p)
    )
    if not paths:
        print('no screenshots found; generate them first', file=sys.stderr)
        return 1

    rows = (len(paths) + COLUMNS - 1) // COLUMNS
    sheet = Image.new(
        'RGB',
        (COLUMNS * (WIDTH + PAD) + PAD, rows * (HEIGHT + PAD + CAPTION) + PAD),
        BACKGROUND,
    )
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(FONT, 22)
    except OSError:
        font = ImageFont.load_default()

    for index, path in enumerate(paths):
        row, column = divmod(index, COLUMNS)
        x = PAD + column * (WIDTH + PAD)
        y = PAD + row * (HEIGHT + PAD + CAPTION)
        sheet.paste(Image.open(path).convert('RGB').resize((WIDTH, HEIGHT), Image.LANCZOS), (x, y))
        draw.rectangle([x, y, x + WIDTH - 1, y + HEIGHT - 1], outline=BORDER)
        draw.text((x, y + HEIGHT + 6), os.path.basename(path)[3:-4].replace('_', ' '), fill=LABEL, font=font)

    sheet.thumbnail((3200, 6000), Image.LANCZOS)
    out = os.path.join(root, 'screenshots', 'contact_sheet.png')
    sheet.save(out, optimize=True)
    print('wrote {} ({} screens, {}x{})'.format(out, len(paths), *sheet.size))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
