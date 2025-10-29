from statistics import geometric_mean

from matplotlib.artist import Artist
from matplotlib.patches import Rectangle
from matplotlib.path import Path

from plot.color import Color
from plot.frame import Frame
from plot.plot import Plot
import seaborn as sns


class ViolinPlot(Plot):

    def __init__(self, frame: Frame):
        super().__init__(frame)

    def plot(self, data: [[float]], colors: [Color]) -> [Artist]:
        if len(data) == 0:
            return

        assert (len(data) == len(colors))

        width = 0.65

        for (i, ys) in enumerate(data):
            mean = geometric_mean(ys)
            # self.ax.text(i + width / 3, float(mean), "\\textbf{" + self.yformatter(mean) + "}", color="black", zorder=30, horizontalalignment="left", verticalalignment='center')
            parts = self.ax.violinplot([data[i]], positions=[i], showmeans=True, showextrema=True, widths=width)

            for partname in ('cbars', 'cmins', 'cmaxes', 'cmeans'):
                parts[partname].set_colors(colors[i])
                parts[partname].set_zorder(20)
                parts[partname].set_linewidth(1)
            parts['cmeans']._paths = [Path(vertices=[(i - width / 3, mean), (i + width / 3, mean)])]

            for pc in parts['bodies']:
                pc.set_color(colors[i])
                pc.set_alpha(0.5)
                pc.set_linewidth(0)
                pc.set_zorder(10)
        sns.swarmplot(data=data, size=1.75, palette=colors)

        return [Rectangle((0, 0), 1, 1, color=color) for color in colors]
