from enum import Enum


class Linestyle(str, Enum):
    SOLID = "solid",
    DOTTED = "dotted",
    DASHED = "dashed",
    DASHDOT = "dashdot"
