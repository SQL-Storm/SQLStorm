from typing import Dict, Set

from matplotlib.artist import Artist
from matplotlib.patches import Rectangle

from plot.barplot import BarPlot
from plot.color import Color
from plot.formatter import Formatter
from plot.frame import Frame
from plot.pattern import Pattern
from plot.plot import Plot


class SplitBarPlot(BarPlot):

    def __init__(self, frames: [Frame]):
        assert len(frames) > 0
        super().__init__(frames[0])
        self.frames = frames
        self.sets = []

    def format_axes(self, set: int, xformatter: Formatter, yformatter: Formatter):
        super().change_frame(self.frames[set])
        super().format_axes(xformatter, yformatter)

    def plot(self, data: [[[float]]], colors: [Color] = None, patterns: [Pattern] = None) -> [Artist]:
        if len(data) == 0:
            return

        ids: Set[int] = set()

        for (s, d) in enumerate(data):
            super().change_frame(self.frames[s])
            self.sets.append([])

            for x, bars in enumerate(d):
                bar_width = self.width / len(bars)
                self.sets[-1].append([])

                for i, y in enumerate(bars):
                    ids.add(i)

                    color = Color.WHITE if colors is None else colors[i]
                    pattern = None if patterns is None else patterns[i]
                    self.sets[-1][-1].append(
                        self.ax.bar([x + 0.5 + (1 - self.width + bar_width) / 2 + i * bar_width], [y], self.width / len(bars), color=color, hatch=pattern, zorder=10, edgecolor=Color.BLACK,
                                    linewidth=self.edgewidth))

            self.ax.axhline(y=0, color='k', linestyle='-', linewidth=1, zorder=20)

        super().change_frame(self.frames[0])

        handles = []
        for i in sorted(ids):
            color = Color.WHITE if colors is None else colors[i]
            pattern = None if patterns is None else patterns[i]
            handles.append(Rectangle((0, 0), 1, 1, facecolor=color, hatch=pattern, edgecolor=Color.BLACK, linewidth=self.edgewidth))

        return handles

    def plotDifference(self, difference: [[str]]):
        assert len(difference) == len(self.sets)
        for (i, s) in enumerate(self.sets):
            super().change_frame(self.frames[i])
            self.bars = s
            super().plotDifference(difference[i])

        super().change_frame(self.frames[0])
