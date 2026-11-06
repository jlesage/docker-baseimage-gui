"""Name row laid under a cursor picture.

The row is RGBA, one byte per channel. Bytes that carry the name are
opaque, with G and B at 0, so a later crop keeps them and premultiplication
does not change R. Magic is VCUR, then version 1, then the cursor name.
"""

MAGIC = b"VCUR"
VERSION = 1

def name_row(name, width):
    """Return width RGBA pixels (a list of 4-tuples) for the name row."""
    payload = MAGIC + bytes((VERSION,)) + name.encode("ascii")
    if width < len(payload):
        raise ValueError("row is narrower than the cursor name")
    row = []
    for i in range(width):
        if i < len(payload):
            row.append((payload[i], 0, 0, 255))
        else:
            row.append((0, 0, 0, 0))
    return row


def decode_name(pixels, width, height):
    """Return the cursor name, or None.

    pixels is a flat sequence of RGBA bytes, or of (r, g, b, a) tuples.
    """
    if height < 1 or width < 5:
        return None
    row = _row_bytes(pixels, width, height)
    for i, magic in enumerate(MAGIC):
        if row[i] != (magic, 0, 0, 255):
            return None
    if row[4] != (VERSION, 0, 0, 255):
        return None
    chars = []
    for pixel in row[5:]:
        r, g, b, a = pixel
        if (r, g, b, a) == (0, 0, 0, 0):
            if any(p != (0, 0, 0, 0) for p in row[5 + len(chars) + 1:]):
                return None
            break
        if g != 0 or b != 0 or a != 255 or r < 0x20 or r > 0x7E:
            return None
        chars.append(chr(r))
    name = "".join(chars)
    from cursors import CURSOR_NAMES
    if name not in CURSOR_NAMES:
        return None
    return name


def _row_bytes(pixels, width, height):
    start = (height - 1) * width
    if pixels and isinstance(pixels[0], tuple):
        return list(pixels[start:start + width])
    raw = pixels
    base = start * 4
    row = []
    for x in range(width):
        i = base + x * 4
        row.append((raw[i], raw[i + 1], raw[i + 2], raw[i + 3]))
    return row
