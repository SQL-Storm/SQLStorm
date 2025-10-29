from enum import Enum


class Marker(str, Enum):
    POINT = ".",
    PIXEL = ",",
    CIRCLE = "o",
    TRIANGLE_DOWN = "v",
    TRIANGLE_UP = "^",
    TRIANGLE_LEFT = "<",
    TRIANGLE_RIGHT = ">",
    TRI_DOWN = "1",
    TRI_UP = "2",
    TRI_LEFT = "3",
    TRI_RIGHT = "4",
    OCTAGON = "8",
    SQUARE = "s",
    PENTAGON = "p",
    PLUS_FILLED = "P",
    STAR = "*",
    HEXAGON = "h",
    HEXAGON_ROTATED = "H",
    PLUS = "+",
    CROSS = "x",
    CROSS_FILLED = "X",
    DIAMOND = "D",
    DIAMOND_THIN = "d"
    LINE_VERTICAL = "|"
