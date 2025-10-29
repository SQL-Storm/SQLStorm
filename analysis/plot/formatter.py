from enum import Enum
from typing import List

import matplotlib
from matplotlib.axes import Axes


class Grid(int, Enum):
    NONE = 1,
    MAJOR = 2,
    MINOR = 3


class Decorator(int, Enum):
    NONE = 1
    TICKS = 2
    TICKLABELS = 3
    AXISLABEL = 4


class TimeUnit(str, Enum):
    NANOSECONDS = "ns",
    MICROSECONDS = "\\textmu{}s",
    MILLISECONDS = "ms",
    SECONDS = "s",
    MINUTES = "m",
    HOURS = "h",
    DAYS = "d",
    MONTHS = "mo",
    YEARS = "y"


class Scale(str, Enum):
    LINEAR = "linear"
    LOG = "log"
    SYMLOG = "symlog"


class TicksPosition(str, Enum):
    LEFT = "left"
    RIGHT = "right"
    BOTTOM = "bottom"
    TOP = "top"
    DEFAULT = "default"


class Formatter(matplotlib.ticker.Formatter):
    def __init__(self, scale: Scale = Scale.LINEAR, ticks: [float] = None, label: str = None, min: float = None, max: float = None, rotation: int = None, grid: Grid = Grid.MINOR,
                 decorator: Decorator = Decorator.AXISLABEL, baseline: float = 0, ticksposition: TicksPosition = TicksPosition.DEFAULT):
        self._scale = scale
        self._ticks = ticks
        self._label = label
        self._min = min
        self._max = max
        self._rotation = rotation
        self._grid = grid
        self._decorator = decorator
        self._baseline = baseline
        self._ticksposition = ticksposition

    def scale(self) -> str:
        return self._scale.value

    def ticks(self) -> [float]:
        return self._ticks

    def label(self) -> str:
        return self._label

    def limit(self) -> (float, float):
        return None if self._min is None or self._max is None else (self._min, self._max)

    def rotation(self) -> float:
        return self._rotation

    def grid(self) -> Grid:
        return self._grid

    def decorator(self) -> Decorator:
        return self._decorator

    def baseline(self) -> float:
        return self._baseline

    def ticksposition(self) -> TicksPosition:
        return self._ticksposition

    def format_axes(self, ax: Axes):
        return

    def __call__(self, x, pos=None):
        return x


class ZoomFormatter(Formatter):
    def __init__(self, formatter: Formatter, min: float, max: float):
        super().__init__(scale=formatter._scale, ticks=formatter._ticks, min=min, max=max, grid=formatter._grid, decorator=Decorator.NONE)


class TimeFormatter(Formatter):
    def __init__(self, scale: Scale = Scale.LINEAR, ticks: [float] = None, label: str = None, min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.MINOR,
                 decorator: Decorator = Decorator.AXISLABEL, time_unit: TimeUnit = TimeUnit.SECONDS, digits=None):
        super().__init__(scale=scale, ticks=ticks, label=label if label is not None else "Time [" + time_unit + "]", min=min, max=max, rotation=rotation, grid=grid, decorator=decorator)
        self._digits = digits

    def __call__(self, x, pos=None):
        if self._digits is None:
            if x < 10:
                x = round(x, 2)
            elif x < 100:
                x = round(x, 1)
            else:
                x = round(x)
        else:
            x = round(x, self._digits)

        if pos is not None and int(x * 100) % 10 == 0:
            x = round(x, 1)
            if int(x * 10) % 10 == 0:
                x = round(x)
        return 0 if x == 0 else x


class ThroughputFormatter(Formatter):
    def __init__(self, scale: Scale = Scale.LINEAR, ticks: [float] = None, label: str = None, min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.MAJOR,
                 decorator: Decorator = Decorator.AXISLABEL, time_unit: TimeUnit = TimeUnit.SECONDS):
        super().__init__(scale=scale, ticks=ticks, label=label if label is not None else "Throughput", min=min, max=max, rotation=rotation, grid=grid, decorator=decorator)

    def __call__(self, x, pos=None):
        sizes = ["", "~K", "~M", "~G", "~T"]
        i = 0
        while x >= 1000:
            i += 1
            x /= 1000

        if x < 10:
            x = round(x, 2)
        elif x < 100:
            x = round(x, 1)
        else:
            x = round(x)

        if pos is not None and int(x * 100) % 10 == 0:
            x = round(x, 1)
            if int(x * 10) % 10 == 0:
                x = round(x)
        return 0 if x == 0 else str(x) + sizes[i]


class NumberFormatter(Formatter):
    def __init__(self, scale: Scale = Scale.LINEAR, ticks: [float] = None, label: str = None, min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.MAJOR,
                 decorator: Decorator = Decorator.AXISLABEL, ticksposition: TicksPosition = TicksPosition.DEFAULT):
        super().__init__(scale=scale, ticks=ticks, label=label, min=min, max=max, rotation=rotation, grid=grid, decorator=decorator, ticksposition=ticksposition)

    def __call__(self, x, pos=None):
        sizes = ["", "~T", "~M", "~B"]
        i = 0
        while x >= 1000:
            i += 1
            x /= 1000

        if x < 10:
            x = round(x, 2)
        elif x < 100:
            x = round(x, 1)
        else:
            x = round(x)

        if pos is not None and int(x * 100) % 10 == 0:
            x = round(x, 1)
            if int(x * 10) % 10 == 0:
                x = round(x)
        return 0 if x == 0 else str(x) + sizes[i]


class ByteFormatter(Formatter):
    def __init__(self, scale: Scale = Scale.LINEAR, ticks: [float] = None, label: str = None, min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.MAJOR,
                 decorator: Decorator = Decorator.AXISLABEL):
        super().__init__(scale=scale, ticks=ticks, label=label if label is not None else "Throughput", min=min, max=max, rotation=rotation, grid=grid, decorator=decorator)

    def __call__(self, x, pos=None):
        sizes = ["~B", "~KB", "~MB", "~GB", "~TB"]
        i = 0
        while x >= 1024:
            i += 1
            x /= 1024

        if x < 10:
            x = round(x, 2)
        elif x < 100:
            x = round(x, 1)
        else:
            x = round(x)

        if pos is not None and int(x * 100) % 10 == 0:
            x = round(x, 1)
            if int(x * 10) % 10 == 0:
                x = round(x)
        return 0 if x == 0 else str(x) + sizes[i]


class SpeedupFormatter(Formatter):
    def __init__(self, scale: Scale = Scale.LINEAR, ticks: [float] = None, label: str = "Speedup [\\%]", min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.MINOR,
                 decorator: Decorator = Decorator.AXISLABEL):
        super().__init__(scale=scale, ticks=ticks, label=label, min=min, max=max, rotation=rotation, grid=grid, baseline=1, decorator=decorator)

    def __call__(self, x, pos=None):
        x = round(x, 2)
        if pos is not None and int(x * 100) % 10 == 0:
            x = round(x, 1)
            if int(x * 10) % 10 == 0:
                x = round(x)
        return ('+' if x > 0 else ('-' if x < 0 else '')) + str(abs(x)) + '\\,\\%'


class PercentFormatter(Formatter):
    def __init__(self, scale: Scale = Scale.LINEAR, ticks: [float] = None, label: str = "Percent [\\%]", min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.MINOR,
                 decorator: Decorator = Decorator.AXISLABEL):
        super().__init__(scale=scale, ticks=ticks, label=label, min=min, max=max, rotation=rotation, grid=grid, decorator=decorator)

    def __call__(self, x, pos=None):
        x = round(x * 100)
        return ('-' if x < 0 else '') + str(abs(x)) + '\,\%'


class LambdaFormatter(Formatter):
    def __init__(self, fn, ticks: [float] = None, scale: Scale = Scale.LINEAR, label: str = None, min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.MAJOR,
                 decorator: Decorator = Decorator.AXISLABEL):
        super().__init__(scale=scale, ticks=ticks, label=label, min=min, max=max, rotation=rotation, grid=grid, decorator=decorator)
        self.fn = fn

    def __call__(self, x, pos=None):
        return self.fn(x)


class LabelFormatter(Formatter):
    def __init__(self, ticklabels: [str], ticks: [float] = None, scale: Scale = Scale.LINEAR, label: str = None, padding: float = 0, min: float = None, max: float = None, rotation: float = None, grid: Grid = Grid.NONE, decorator: Decorator = Decorator.AXISLABEL):
        super().__init__(scale=scale, ticks=[x for x in range(len(ticklabels))] if ticks is None else ticks, label=label, min=(-0.5 - padding if min is None else None),
                         max=(len(ticklabels) - 0.5 + padding if max is None else max), rotation=rotation, grid=grid, decorator=decorator)
        self._ticklabels = ticklabels

    def __call__(self, x, pos=None):
        return self._ticklabels[x]


class ReverseLabelFormatter(Formatter):
    def __init__(self, ticklabels: [str], label: str = None, padding: float = 0, rotation: float = None, grid: Grid = Grid.NONE, decorator: Decorator = Decorator.AXISLABEL):
        super().__init__(ticks=[x for x in range(len(ticklabels))], label=label, min=len(ticklabels) - 0.5 + padding, max=-0.5 - padding, rotation=rotation, grid=grid, decorator=decorator)
        self._ticklabels = ticklabels

    def __call__(self, x, pos=None):
        return self._ticklabels[x]


class ThreadFormatter(LabelFormatter):
    def __init__(self, num_threads: int, padding: float = 0):
        super().__init__(ticklabels=[str(num_threads - i) for i in range(num_threads)], label="Thread", padding=padding, grid=Grid.NONE)


class ThreadsFormatter(Formatter):
    def __init__(self, ticks: List[int] = None, label: str = None,  padding: float = 0, rotation: float = None, grid: Grid = Grid.NONE, decorator: Decorator = Decorator.AXISLABEL, hyperthreads: int = None):
        super().__init__(ticks=ticks, label=label if label is not None else "Number of Threads",
                         min=ticks[0] - 1 - padding, max=ticks[-1] + 1 + padding, rotation=rotation, grid=grid, decorator=decorator)
        self.hyperthreads = hyperthreads

    def format_axes(self, ax: Axes):
        if self.hyperthreads is not None:
            ax.axvline(self.hyperthreads, color="darkgray", linestyle="--", linewidth=0.75, zorder=1)

    def __call__(self, x, pos=None):
        return x
