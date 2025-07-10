import os
from typing import Any

from rich.console import Console
from rich.highlighter import ReprHighlighter
from rich.progress import Progress, TextColumn, BarColumn, TaskProgressColumn, ProgressColumn
from rich.prompt import Confirm
from rich.table import Table, Column
from rich.text import Text


class Log:
    """
    A class to manage logging messages with different severity levels and progress tracking.
    """

    def __init__(self):
        self.highlighter = ReprHighlighter()

        self.verbose = os.environ.get('VERBOSE', 'false').lower() in ['true', '1']
        self._file = os.environ.get('LOG_FILE', None)

        if self._file:
            self.console = Console(file=open(self._file, "w"), no_color=True, color_system="standard", force_jupyter=False, force_interactive=False, log_path=False, width=120)
        else:
            self.console = Console(force_jupyter=False, log_path=False)

    def print(self, *info: Any):
        """
        Prints a message to the console.

        Args:
            info (Any): The information to print.
        """
        self.console.print(*info)

    def log_group(self, info: Any, group: str, group_color: str):
        """
        Logs a message in a formatted table with a specific group and color.

        Args:
            info (Any): The information to log.
            group (str): The group name (e.g., "error", "warning", "info").
            group_color (str): The color associated with the group.
        """
        table = Table(show_header=False, box=None)
        table.add_column("c1", min_width=10)
        table.add_column("c2", overflow="fold")

        text = self.highlighter(info) if isinstance(info, str) else info
        table.add_row(f'[bold {group_color}]{group.upper()}[/]', text)

        self.console.log(table, _stack_offset=3)

    def error(self, info: Any):
        """
        Logs an error message.

        Args:
            info (Any): The error information to log.
        """
        self.log_group(str(info).strip(), "error", "red")

    def warn(self, info: Any):
        """
        Logs a warning message.

        Args:
            info (Any): The warning information to log.
        """
        self.log_group(info, "warning", "bright_green")

    def confirm(self, info: Any):
        """
        Asks for user confirmation and logs the question.

        Args:
            info (Any): The confirmation question to ask.

        Returns:
            bool: True if the user confirms, False otherwise.
        """
        answer = Confirm.ask(str(info), default=False)
        if answer:
            self.console.print(Text(" " * len(str(info))))
        return answer

    def info(self, info: Any = ""):
        """
        Logs an informational message.

        Args:
            info (Any): The information to log.
        """
        self.log_group(info, "info", "yellow")

    def info_verbose(self, info: Any = ""):
        """
        Logs an informational message if verbose mode is enabled.

        Args:
            info (Any): The information to log.
        """
        if self.verbose:
            self.info(info)

    def header(self, text: str):
        """
        Logs a header message with a rule.

        Args:
            text (str): The header text to log.
        """
        self.console.rule(f'[bold]{text}[/]')

    def header2(self, text: str):
        """
        Logs a secondary header message with a rule.

        Args:
            text (str): The header text to log.
        """
        self.console.rule(f'{text}')
        if self.file:
            self.file_console.rule(f'{text}')

    def newline(self):
        """
        Logs a newline.
        """
        self.console.print('')

    class LogProgress:
        """
        A class to manage and display progress logging.
        """

        class MofNCompleteColumn(ProgressColumn):
            """
            A custom progress column to display completed tasks out of total tasks.
            """

            def __init__(self, base: int):
                super().__init__(table_column=None)
                self._base = base

            def render(self, task: "Task") -> Text:
                completed = int(task.completed / self._base)
                total = int(task.total / self._base) if task.total is not None else "?"
                total_width = len(str(total))
                return Text(f"[{completed:{total_width}d}/{total}]", style="progress.download")

        class TimeColumn(ProgressColumn):
            """
            A custom progress column to display elapsed and remaining time.
            """
            max_refresh = 0.5  # Only refresh twice a second to prevent jitter

            def render(self, task: "Task") -> Text:
                def format_time(prefix: str, time: float, style: str) -> Text:
                    if time is None:
                        return Text("--:--", style=style)

                    minutes, seconds = divmod(int(time), 60)
                    hours, minutes = divmod(minutes, 60)

                    if not hours:
                        formatted = f"{minutes:02d}:{seconds:02d}"
                    else:
                        formatted = f"{hours:d}:{minutes:02d}:{seconds:02d}"

                    return Text(f'{prefix}: {formatted}', style=style)

                remaining = format_time("remaining", task.time_remaining, "progress.remaining")
                elapsed = format_time("elapsed", task.elapsed, "progress.remaining")

                return Text.assemble("(", remaining, ", ", elapsed, ")")

        def __init__(self, log: "Log", info: str, total: int, base: int = 1):
            """
            Initializes the LogProgress instance.

            Args:
                log (Log): The Log instance to use for logging.
                info (str): The description of the progress task.
                total (int): The total number of steps in the progress task.
                base (int): The base value for the MofNCompleteColumn.
            """
            self._log = log
            self._info = info
            self._total = total
            self._base = base

        def __enter__(self):
            """
            Starts the progress logging.
            """
            self.progress = Progress(
                self.MofNCompleteColumn(self._base),
                TextColumn("[progress.description]{task.description}", table_column=Column(no_wrap=True, width=25)),
                BarColumn(),
                TaskProgressColumn(),
                self.TimeColumn(),
                transient=True,
                console=self._log.console,
            )
            self.progress.start()
            self.task = self.progress.add_task(self._info, total=self._total)
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            """
            Stops the progress logging.
            """
            self.progress.stop()

        def description(self, info: str):
            """
            Updates the description of the progress task.

            Args:
                info (str): The new description.
            """
            self.progress.update(self.task, description=info)

        def advance(self):
            """
            Advances the progress task by one step.
            """
            self.progress.update(self.task, advance=1)

        def completed(self, completed: int):
            """
            Sets the completed steps of the progress task.

            Args:
                completed (int): The number of completed steps.
            """
            self.progress.update(self.task, completed=completed)

    def progress(self, info: str, total: int, base: int = 1) -> LogProgress:
        """
        Creates a progress logging context manager.

        Args:
            info (str): The description of the progress task.
            total (int): The total number of steps in the progress task.
            base (int): The base value for the MofNCompleteColumn.

        Returns:
            LogProgress: The LogProgress instance.
        """
        return self.LogProgress(self, info, total, base)

    class LogFile:
        """
        A class to manage logging to a file.
        """

        def __init__(self, log: "Log", file: str):
            """
            Initializes the LogFile instance.

            Args:
                log (Log): The Log instance to use for logging.
                file (str): The file path to log to.
            """
            self._log = log
            self._file = file
            self._old_console = None
            self._log_file = None

        def __enter__(self):
            """
            Opens the log file for writing.
            """
            self._old_console = self._log.console
            self._log_file = open(self._file, "w")
            self._log.console = Console(file=self._log_file, no_color=True, color_system="standard", force_jupyter=False, force_interactive=False, log_path=False, width=120)
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            """
            Closes the log file.
            """
            if self._old_console:
                self._log.console = self._old_console
            if self._log_file:
                self._log_file.close()

    def file(self, file: str) -> LogFile:
        """
        Creates a LogFile context manager for logging to a file.

        Args:
            file (str): The file path to log to.

        Returns:
            LogFile: The LogFile instance.
        """
        return self.LogFile(self, file)


log = Log()
