"""Read and write the Xcursor file images this generator needs."""

import struct

MAGIC = 0x72756358  # "Xcur"
IMAGE_TYPE = 0xFFFD0002
FILE_VERSION = 0x00010000


def read_images(path):
    data = open(path, "rb").read()
    if len(data) < 16:
        raise ValueError("short Xcursor file: %s" % path)
    magic, header, version, ntoc = struct.unpack_from("<IIII", data, 0)
    if magic != MAGIC or header < 16 or header + ntoc * 12 > len(data):
        raise ValueError("not an Xcursor file: %s" % path)
    images = []
    off = header
    for _ in range(ntoc):
        typ, subtype, pos = struct.unpack_from("<III", data, off)
        off += 12
        if typ != IMAGE_TYPE:
            continue
        if pos + 36 > len(data):
            raise ValueError("truncated image in %s" % path)
        fields = struct.unpack_from("<IIIIIIIII", data, pos)
        header_size, _, _, _, width, height, xhot, yhot, _delay = fields
        nbytes = width * height * 4
        start = pos + header_size
        if start + nbytes > len(data):
            raise ValueError("truncated pixels in %s" % path)
        pixels = []
        for i in range(width * height):
            argb = struct.unpack_from("<I", data, start + i * 4)[0]
            pixels.append((
                (argb >> 16) & 255,
                (argb >> 8) & 255,
                argb & 255,
                (argb >> 24) & 255,
            ))
        images.append({
            "size": subtype,
            "width": width,
            "height": height,
            "xhot": xhot,
            "yhot": yhot,
            "pixels": pixels,
        })
    if not images:
        raise ValueError("no cursor image in %s" % path)
    return images


def closest(images, nominal=24):
    """The image whose nominal size is closest to nominal. Ties take the smaller size, then the first."""
    best = None
    for image in images:
        key = (abs(image["size"] - nominal), image["size"])
        if best is None or key < best[0]:
            best = (key, image)
    return best[1]


def write_image(path, image):
    """Write one static Xcursor image. image pixels are RGBA tuples."""
    width = image["width"]
    height = image["height"]
    pixels = image["pixels"]
    if len(pixels) != width * height:
        raise ValueError("pixel count does not match the size")
    header = struct.pack("<IIII", MAGIC, 16, FILE_VERSION, 1)
    # Image chunk follows the 16-byte header and one 12-byte toc entry.
    position = 16 + 12
    toc = struct.pack("<III", IMAGE_TYPE, image["size"], position)
    chunk = struct.pack(
        "<IIIIIIIII",
        36,
        IMAGE_TYPE,
        image["size"],
        1,
        width,
        height,
        image["xhot"],
        image["yhot"],
        0,
    )
    raw = bytearray()
    for r, g, b, a in pixels:
        raw += struct.pack("<I", (a << 24) | (r << 16) | (g << 8) | b)
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(toc)
        fh.write(chunk)
        fh.write(raw)
