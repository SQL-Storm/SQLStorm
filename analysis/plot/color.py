from enum import Enum


def blend(color: int, factor: float) -> int:
    return int(255 - (255 - color) * factor)


def rgb(red: int, green: int, blue: int, factor: float = 1) -> str:
    """Return color as #rrggbb for the given color values."""
    return '#%02x%02x%02x' % (blend(red, factor), blend(green, factor), blend(blue, factor))


class Color(str, Enum):
    BLACK = rgb(0, 0, 0),
    DARKGRAY = rgb(64, 64, 64),
    GRAY = rgb(127, 127, 127),
    LIGHTGRAY = rgb(191, 191, 191),
    WHITE = rgb(255, 255, 255),
    BLUE = rgb(55, 126, 184),
    DARKBLUE = rgb(35, 80, 122),
    GREEN = rgb(77, 175, 74),
    ORANGE = rgb(255, 127, 0),
    YELLOW = rgb(255, 210, 0),
    RED = rgb(205, 22, 28),
    VIOLET = rgb(103, 53, 111),
    TURQUOISE = rgb(69, 226, 205)
    PINK = rgb(240, 40, 240)
    LIGHTBLUE = rgb(55, 126, 184, 0.6),
    LIGHTGREEN = rgb(77, 175, 74, 0.6),
    LIGHTORANGE = rgb(255, 127, 0, 0.85),
    LIGHTYELLOW = rgb(255, 210, 0, 0.6),
    LIGHTRED = rgb(205, 22, 28, 0.75),
    LIGHTVIOLET = rgb(103, 53, 111, 0.6)

    #    'xor': "#CD161C",
    #    'bloom': "#23507A",
    #    'lightbloom': rgb(35, 80, 122, 0.6),
    #    'fuse': "#29021d",
    #    'lightviolet': "#984EA3",
    #    'violet': "#67356F",
    #    'lightgreen': "#4DAF4A",
    #    'green': "#3C893A",

    TUMBLUE = "#0065BD",
    TUMSECONDARYBLUE1 = "#005293",
    TUMSECONDARYBLUE2 = "#003359",
    TUMDARKGRAY = "#333333",
    TUMGRAY = "#808080",
    TUMLIGHTGRAY = "#CCCCCC",
    TUMORANGE = "#E37222",
    TUMGREEN = "#A2AD00",
    TUMLIGHTBLUE = "#98C6EA",
    TUMACCENTGRAY = "#DAD7CB",
    TUMACCENTBLUE = "#64A0C8",

#    DARKBLUE = "#23507A",
#    ORANGE = "#FF7F00",
#    RED = "#CD161C",
#    GREEN = "#3C893A",
#    VIOLET = "#984EA3",
#    BLACK = "#29021d",
#    WHITE = "#000000",
#    YELLOW = "#FFD200",
#    LIGHTGRAY = "#DAD7CB",
#    LIGHTBLUE = "#98C6EA",

    MAXORANGE = "#FFB800",
    MAXGREEN = "#7CB84C",
    MAXRED = "#EC6B6D"
    MAXBLUE = "#489DF4"
