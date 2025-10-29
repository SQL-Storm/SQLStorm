import numpy as np
from matplotlib.artist import Artist
from matplotlib.patches import Rectangle

from plot.color import Color
from plot.frame import Frame
from plot.plot import Plot


class HistogramPlot(Plot):

    def __init__(self, frame: Frame):
        super().__init__(frame)

    def plot(self, data: [float], num_bins: int = 10):
        if len(data) == 0:
            return

        return self.ax.hist(data, bins=num_bins, zorder=10)[2]

    def table(self, data: [[float]], intervals: [(float, float)], colors: [Color]) -> [Artist]:
        if len(data) == 0:
            return

        assert (len(data) == len(colors))

        histogram: [[int]] = [[0 for _ in range(len(intervals))] for _ in range(len(data))]
        for (i, ys) in enumerate(data):
            for y in ys:
                for (j, interval) in enumerate(intervals):
                    if interval[0] <= y < interval[1]:
                        histogram[i][j] += 1
                        break

        print(histogram)

        for (y, h) in enumerate(histogram):
            for (x, count) in enumerate(h):
                self.ax.add_patch(Rectangle((x + 0.5, y + 0.5), 1, 1, facecolor=colors[y], linewidth=0, alpha=count / sum(histogram[y])))
                self.ax.text(x + 1, y + 1, count, color="black", zorder=30, horizontalalignment='center', verticalalignment='center')

        return []

    def annotate(self, annotations: [str]):
        assert int(self.ax.get_ylim()[1] - self.ax.get_ylim()[0]) == len(annotations)

        x = self.ax.get_xlim()[1] + 0.25
        for (y, annotation) in enumerate(annotations):
            self.ax.text(x, y + 1, annotation, color="black", zorder=30, horizontalalignment='left', verticalalignment='center')
