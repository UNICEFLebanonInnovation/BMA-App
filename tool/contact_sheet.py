#!/usr/bin/env python3
"""Assemble the screenshot contact sheets, one per device class.

The app is tablet-first for a 9-inch Android tablet, with the phone kept as a
supported fallback, so there is no single sheet that can show everything: the
three device classes have three different aspect ratios and every thumbnail is
resized with ``Image.LANCZOS`` to the sheet's cell size. Mixing 1280x800 into a
412x915 grid does not letterbox it, it SQUASHES it — the old single-sheet
script worked only because it excluded every ``*_tablet*.png`` outright.

So: ONE ASPECT RATIO PER SHEET.

    --mode tablet-landscape  ->  contact_sheet_tablet_landscape.png
                                 1280x800, 2 columns, *_tablet_landscape*.png
                                 (the headline sheet and the README image)
    --mode tablet-portrait   ->  contact_sheet_tablet_portrait.png
                                 800x1280, 3 columns, *_tablet*.png minus the
                                 landscape ones
    --mode phone             ->  contact_sheet.png
                                 412x915, 5 columns, everything else — the
                                 documented phone fallback, unchanged output

With no --mode, all three are built.

Run after regenerating the screenshots:

    BMA_SCREENSHOTS=1 flutter test test/screenshots/screenshot_generator_test.dart
    python3 tool/contact_sheet.py

Needs Pillow.
"""

import argparse
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

PAD, CAPTION = 24, 34
BACKGROUND = (244, 247, 246)
BORDER = (200, 205, 210)
LABEL = (0, 51, 102)
FONT = '/home/user/tools/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf'
MAX_SHEET = (3200, 6000)
ASPECT_TOLERANCE = 0.01

# The landscape suffix deliberately contains '_tablet', so "portrait tablet" is
# "contains _tablet, does not contain _tablet_landscape" and "phone" stays the
# original "does not contain _tablet" — the phone sheet's filter is untouched.
LANDSCAPE = '_tablet_landscape'
TABLET = '_tablet'

MODES = {
    'phone': {
        'size': (412, 915),
        'columns': 5,
        'output': 'contact_sheet.png',
        'keep': lambda name: TABLET not in name,
        'title': 'phone fallback (412x915)',
    },
    'tablet-landscape': {
        'size': (1280, 800),
        'columns': 2,
        'output': 'contact_sheet_tablet_landscape.png',
        'keep': lambda name: LANDSCAPE in name,
        'title': '9" tablet landscape (1280x800)',
    },
    'tablet-portrait': {
        'size': (800, 1280),
        'columns': 3,
        'output': 'contact_sheet_tablet_portrait.png',
        'keep': lambda name: TABLET in name and LANDSCAPE not in name,
        'title': '9" tablet portrait (800x1280)',
    },
}


def captures(root, keep):
    """The NN_*.png captures the harness writes, in capture order."""
    return sorted(
        path for path in glob.glob(os.path.join(root, 'screenshots', '[0-9][0-9]_*.png'))
        if keep(os.path.basename(path))
    )


def build(root, mode):
    spec = MODES[mode]
    width, height = spec['size']
    columns = spec['columns']
    paths = captures(root, spec['keep'])
    if not paths:
        print('{}: no captures match; generate them first'.format(mode), file=sys.stderr)
        return None

    rows = (len(paths) + columns - 1) // columns
    sheet = Image.new(
        'RGB',
        (columns * (width + PAD) + PAD, rows * (height + PAD + CAPTION) + PAD),
        BACKGROUND,
    )
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(FONT, 22)
    except OSError:
        font = ImageFont.load_default()

    for index, path in enumerate(paths):
        row, column = divmod(index, columns)
        x = PAD + column * (width + PAD)
        y = PAD + row * (height + PAD + CAPTION)
        shot = Image.open(path).convert('RGB')
        # A capture in the wrong aspect ratio would be silently SQUASHED by the
        # resize below, which is exactly the defect this rewrite exists to
        # remove. Warn instead of producing a quietly wrong sheet. The tolerance
        # is there because a capture is (logical size x dpr) rounded to whole
        # device pixels: 412x915 at dpr 2.625 lands on 1082x2402, not 1082.0625.
        if abs(shot.width / shot.height - width / height) > ASPECT_TOLERANCE:
            print(
                '{}: {} is {}x{}, which is not the {}x{} aspect of this sheet — '
                'the resize would distort it'.format(
                    mode, os.path.basename(path), shot.width, shot.height, width, height),
                file=sys.stderr,
            )
        sheet.paste(shot.resize((width, height), Image.LANCZOS), (x, y))
        draw.rectangle([x, y, x + width - 1, y + height - 1], outline=BORDER)
        draw.text((x, y + height + 6), os.path.basename(path)[3:-4].replace('_', ' '), fill=LABEL, font=font)

    sheet.thumbnail(MAX_SHEET, Image.LANCZOS)
    out = os.path.join(root, 'screenshots', spec['output'])
    sheet.save(out, optimize=True)
    print('wrote {} ({} screens, {}, {}x{})'.format(out, len(paths), spec['title'], *sheet.size))
    return out


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        '--mode',
        choices=sorted(MODES),
        action='append',
        help='which sheet to build; repeatable. Default: all three.',
    )
    args = parser.parse_args(argv)
    modes = args.mode or sorted(MODES)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    failed = 0
    for mode in modes:
        if build(root, mode) is None:
            failed += 1
    # Building every sheet must not fail just because one device class has not
    # been captured yet; a single explicit --mode that finds nothing is an error.
    if failed and (args.mode or failed == len(modes)):
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
