import seaborn as sns
from matplotlib.artist import Artist
from matplotlib.patches import Rectangle

from plot.color import Color
from plot.frame import Frame
from plot.plot import Plot


class BoxPlot(Plot):

    def __init__(self, frame: Frame, boxwidth: float = 0.8, linewidth: float = 1.0, pointsize: float = 0.75):
        super().__init__(frame)
        self.boxwidth = boxwidth
        self.linewidth = linewidth
        self.outliersize = pointsize

    def plot(self, data: [[float]], colors: list[Color] = [Color.WHITE], linecolor=Color.BLACK) -> [Artist]:
        if len(data) == 0:
            return

        if len(colors) == 1:
            colors = colors * len(data)

        props = {"zorder": 10}
        sns.boxplot(data=data, ax=self.ax,
                    width=self.boxwidth, linewidth=self.linewidth,
                    fliersize=self.outliersize, whis=[5, 95],
                    linecolor=linecolor, palette=colors,
                    boxprops=props, whiskerprops=props, medianprops=props)
        self.reformat_axes()
        self.ax.axhline(y=(1 if self.ax.yaxis.get_scale() == 'log' else 0), color='k', linestyle='-', linewidth=1, zorder=5)

        return [Rectangle((0, 0), 1, 1, color=color) for color in colors] if colors is not None else None

    def plotHorizontal(self, data: [[float]], colors: [Color] = None) -> [Artist]:
        if len(data) == 0:
            return

        props = {"zorder": 10}
        sns.boxplot(data=data, orient='h', width=self.boxwidth, linewidth=self.linewidth, fliersize=self.outliersize, whis=[5, 95], palette=colors, boxprops=props, whiskerprops=props,
                    medianprops=props, ax=self.ax)

        return [Rectangle((0, 0), 1, 1, color=color) for color in colors] if colors is not None else None
