from enum import Enum


class Pattern(str, Enum):
    NONE = "",
    DIAGONAL = "/",
    BACK_DIAGONAL = "\\",
    VERTICAL = "|",
    HORIZONTAL = "-",
    CROSSED = "+",
    CROSSED_DIAGONAL = "x",
    SMALL_CIRCLES = 'o',
    LARGE_CIRCLES = 'O',
    DOTS = ".",
    STARS = "*"
    DENSE_DIAGONAL = "////",
    DENSE_BACK_DIAGONAL = "\\\\\\\\",
    DENSE_VERTICAL = "||||",
    DENSE_HORIZONTAL = "----",
    DENSE_CROSSED = "++++",
    DENSE_CROSSED_DIAGONAL = "xxxx",
    DENSE_SMALL_CIRCLES = 'oooo',
    DENSE_LARGE_CIRCLES = 'OOOO',
    DENSE_DOTS = "....",
    DENSE_STARS = "****"
