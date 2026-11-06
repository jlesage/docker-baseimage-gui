#!/usr/bin/env python3
"""Build the viewer-cursor theme from Breeze pictures plus a name row."""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cursors  # noqa: E402
import row  # noqa: E402
import xcursor  # noqa: E402

NOMINAL = 24


def load_picture(cursor_dir, cursor_file):
    path = os.path.join(cursor_dir, cursor_file)
    if not os.path.exists(path):
        raise SystemExit("missing Breeze cursor: %s" % path)
    image = xcursor.closest(xcursor.read_images(path), NOMINAL)
    return image


def with_name_row(picture, name):
    payload = len(row.MAGIC) + 1 + len(name)
    width = picture["width"] if picture else payload
    if width < payload:
        width = payload
    height = 0 if picture is None else picture["height"]
    pixels = []
    if picture is not None:
        src = picture["pixels"]
        for y in range(picture["height"]):
            for x in range(width):
                if x < picture["width"]:
                    pixels.append(src[y * picture["width"] + x])
                else:
                    pixels.append((0, 0, 0, 0))
    pixels.extend(row.name_row(name, width))
    xhot = 0 if picture is None else picture["xhot"]
    yhot = 0 if picture is None else picture["yhot"]
    if picture is not None and (xhot >= width or yhot >= height):
        raise SystemExit("hotspot falls outside the picture for %s" % name)
    return {
        "size": NOMINAL if picture is None else picture["size"],
        "width": width,
        "height": height + 1,
        "xhot": xhot,
        "yhot": yhot,
        "pixels": pixels,
    }


def build(cursor_dir, out_dir):
    out_cursor_dir = os.path.join(out_dir, "cursors")
    os.makedirs(out_cursor_dir, exist_ok=True)
    theme = os.path.join(out_dir, "index.theme")
    with open(theme, "w", encoding="ascii") as fh:
        fh.write("[Icon Theme]\n")
        fh.write("Name=viewer-cursor\n")
        fh.write("Inherits=default\n")
    written = []
    for theme_file, cursor_name, source_file in cursors.rows():
        picture = None
        if source_file is not None:
            picture = load_picture(cursor_dir, source_file)
        image = with_name_row(picture, cursor_name)
        dest = os.path.join(out_cursor_dir, theme_file)
        xcursor.write_image(dest, image)
        written.append((theme_file, cursor_name, source_file, image))
    return written


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cursors", required=True, help="Breeze cursors directory")
    parser.add_argument("--out", required=True, help="Theme directory to write")
    args = parser.parse_args()
    written = build(args.cursors, args.out)
    print("wrote %d cursors to %s" % (len(written), args.out))


if __name__ == "__main__":
    main()
