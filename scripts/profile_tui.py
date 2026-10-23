"""Small keyboard-driven profile panes; no terminal dependencies beyond Python."""
import contextlib
import os
import select
import shutil
import sys
import termios
import tty
import textwrap


@contextlib.contextmanager
def keyboard():
    descriptor = sys.stdin.fileno()
    original = termios.tcgetattr(descriptor)
    try:
        tty.setcbreak(descriptor, termios.TCSANOW)
        sys.stdout.write('\033[?25l'); sys.stdout.flush()
        yield
    finally:
        termios.tcsetattr(descriptor, termios.TCSADRAIN, original)
        sys.stdout.write('\033[?25h\033[0m'); sys.stdout.flush()


def key(timeout=None):
    if not select.select([sys.stdin], [], [], timeout)[0]:
        return ''
    value = os.read(sys.stdin.fileno(), 1).decode(errors='ignore')
    if value == '\x1b':
        rest = b''
        while select.select([sys.stdin], [], [], .025)[0]:
            rest += os.read(sys.stdin.fileno(), 1)
            if len(rest) >= 2:
                break
        return {b'[A': 'up', b'[B': 'down', b'[D': 'back', b'[C': 'enter'}.get(rest, 'back')
    if value in ('\r', '\n', ' '): return 'enter'
    if value in ('\x03', 'q', 'Q'): raise SystemExit(130)
    return value.lower()


def clean(value):
    return ''.join(c for c in str(value) if c.isprintable())


def frame(title, rows, selected, details, footer, size=None):
    width, height = size or shutil.get_terminal_size((80, 24))
    width = max(20, width); height = max(8, height)
    footer_lines = textwrap.wrap(clean(footer), width=width) if footer else []
    navigation = textwrap.wrap('↑↓ Move  Enter Open  B Back  Q Cancel', width=width)
    lines = [clean(title)[:width], '─' * width]
    room = max(1, height - 3 - len(footer_lines) - len(navigation) - (2 if width < 76 else 0))
    start = max(0, selected - room + 1)
    visible = rows[start:start + room]
    if width >= 76:
        left = min(36, width // 2)
        for index in range(max(len(visible), min(len(details), room))):
            label = ('› ' if start + index == selected else '  ') + clean(visible[index][0]) if index < len(visible) else ''
            detail = clean(details[index]) if index < len(details) else ''
            lines.append(label[:left].ljust(left) + ' │ ' + detail[:width-left-3])
    else:
        lines.extend(clean(line)[:width] for line in details[:2])
        lines.extend((('› ' if start + i == selected else '  ') + clean(row[0]))[:width] for i, row in enumerate(visible))
    lines += ['─' * width, *footer_lines, *navigation]
    return '\n'.join(line[:width] for line in lines[:height])


def show(value):
    sys.stdout.write('\033[H\033[2J' + value + '\n'); sys.stdout.flush()


def choose(title, rows, detail=lambda item: [], actions=''):
    """Return (key, value). Rows are labels and opaque values; no side effects."""
    if not rows:
        rows = [('No entries yet', None)]
    selected = 0
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print(title)
        for index, (label, _) in enumerate(rows, 1): print(f'{index}. {label}')
        from setup_prompts import prompt
        answer = prompt('Number, action, or B Back: ').lower()
        if answer.isdigit() and 1 <= int(answer) <= len(rows): return 'enter', rows[int(answer)-1][1]
        return answer, rows[0][1]
    with keyboard():
        while True:
            show(frame(title, rows, selected, detail(rows[selected][1]), actions))
            value = key()
            if value in ('up', 'k'): selected = (selected - 1) % len(rows)
            elif value in ('down', 'j'): selected = (selected + 1) % len(rows)
            elif value in ('b', 'back'): return 'b', None
            elif value: return value, rows[selected][1]


def message(title, lines, footer):
    """A full-width progress pane for URLs, device codes, and action feedback."""
    width, height = shutil.get_terminal_size((80, 24))
    width = max(20, width)
    rendered = [clean(title)[:width], '─' * width]
    for line in lines:
        rendered.extend(textwrap.wrap(clean(line), width=width) or [''])
    rendered += ['─' * width, *textwrap.wrap(footer, width=width)]
    return '\n'.join(rendered[:height])
