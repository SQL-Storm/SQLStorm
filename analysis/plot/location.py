from enum import Enum


class Location(str, Enum):
    BEST = "best",
    UPPER_RIGHT = "upper right",
    UPPER_LEFT = "upper left",
    LOWER_LEFT = "lower left",
    LOWER_RIGHT = "lower right",
    RIGHT = "right",
    CENTER_LEFT = "center left",
    CENTER_RIGHT = "center right",
    LOWER_CENTER = "lower center",
    UPPER_CENTER = "upper center",
    CENTER = "center"
