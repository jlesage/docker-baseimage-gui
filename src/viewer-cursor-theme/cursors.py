# Theme file, cursor name spelled in the last row, Breeze file for the
# picture. None means the file is only the name row.

CURSOR_NAMES = (
    "auto",
    "default",
    "none",
    "context-menu",
    "help",
    "pointer",
    "progress",
    "wait",
    "cell",
    "crosshair",
    "text",
    "vertical-text",
    "alias",
    "copy",
    "move",
    "no-drop",
    "not-allowed",
    "grab",
    "grabbing",
    "e-resize",
    "n-resize",
    "ne-resize",
    "nw-resize",
    "s-resize",
    "se-resize",
    "sw-resize",
    "w-resize",
    "ew-resize",
    "ns-resize",
    "nesw-resize",
    "nwse-resize",
    "col-resize",
    "row-resize",
    "all-scroll",
    "zoom-in",
    "zoom-out",
)

EXTRA = (
    ("left_ptr", "default", "left_ptr"),
    ("dnd-none", "no-drop", "no-drop"),
    ("dnd-no-drop", "no-drop", "no-drop"),
    ("dnd-copy", "copy", "copy"),
    ("dnd-move", "move", "move"),
    ("dnd-link", "alias", "alias"),
    ("left_ptr_watch", "progress", "left_ptr_watch"),
    ("watch", "wait", "watch"),
    ("fleur", "move", "fleur"),
    ("top_side", "ns-resize", "top_side"),
    ("bottom_side", "ns-resize", "bottom_side"),
    ("left_side", "ew-resize", "left_side"),
    ("right_side", "ew-resize", "right_side"),
    ("top_left_corner", "nwse-resize", "top_left_corner"),
    ("bottom_right_corner", "nwse-resize", "bottom_right_corner"),
    ("top_right_corner", "nesw-resize", "top_right_corner"),
    ("bottom_left_corner", "nesw-resize", "bottom_left_corner"),
)


def rows():
    """Yield (theme file, cursor name, Breeze file or None)."""
    for name in CURSOR_NAMES:
        if name == "none":
            yield name, name, None
        elif name == "auto":
            yield name, name, "default"
        else:
            yield name, name, name
    for item in EXTRA:
        yield item
