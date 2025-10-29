from matplotlib.artist import Artist
from matplotlib.patches import Rectangle

from plot.color import Color
from plot.frame import Frame
from plot.pattern import Pattern
from plot.plot import Plot


class MorselPlot(Plot):

    def __init__(self, frame: Frame):
        super().__init__(frame)

    def plot(self, data: [[(float, float, int)]], colors: [Color] = None, patterns: [Pattern] = None) -> [Artist]:
        height = 0.8
        linewidth = 1

        ids = set()

        for (thread, morsels) in enumerate(data):
            for (start, duration, id) in morsels:
                color = Color.WHITE if colors is None else colors[id]
                pattern = None if patterns is None else patterns[id]
                rect = Rectangle((start, len(data) - thread - 1 - height / 2), width=duration, height=height, linewidth=linewidth, edgecolor=Color.BLACK, facecolor=color, hatch=pattern)
                ids.add(id)
                self.ax.add_patch(rect)
                if id == 5:
                    rx, ry = rect.get_xy()
                    cx = rx + rect.get_width() / 2.0
                    cy = ry + rect.get_height() / 2.25
                    self.ax.annotate("LLVM compilation", (cx, cy), color='#F0F0F0F0', fontsize=8, ha='center', va='center')

        handles = []
        for id in sorted(ids):
            color = Color.WHITE if colors is None else colors[id]
            pattern = None if patterns is None else patterns[id]
            handles.append(Rectangle((0, 0), 1, 1, linewidth=linewidth, edgecolor=Color.BLACK, facecolor=color, hatch=pattern))

        return handles
