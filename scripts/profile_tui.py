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
            if len(rest) >= 2 and (rest[-1:] in (b'~', b'A', b'B', b'C', b'D') or len(rest) >= 4):
                break
        return {b'[A': 'up', b'[B': 'down', b'[D': 'back', b'[C': 'enter', b'[5~': 'pageup', b'[6~': 'pagedown'}.get(rest, 'back')
    if value in ('\r', '\n', ' '): return 'enter'
    if value in ('\x03', 'q', 'Q'): raise SystemExit(130)
    return value.lower()


def clean(value):
    return ''.join(c for c in str(value) if c.isprintable())


def frame(title, rows, selected, details, footer, size=None, detail_offset=0):
    width, height = size or shutil.get_terminal_size((80, 24))
    width = max(20, width); height = max(8, height)
    footer_lines = textwrap.wrap(clean(footer), width=width) if footer else []
    navigation = ['']
    for hint in ('↑↓ Move', 'Enter Open', 'B Back', 'Q Cancel', 'PgUp/PgDn About'):
        if navigation[-1] and len(navigation[-1]) + 2 + len(hint) > width: navigation.append(hint)
        else: navigation[-1] += ('  ' if navigation[-1] else '') + hint
    inner = max(1, width - 4)
    def border(label):
        label = ('─ ' + label + ' ')[:width-2]
        return '╭' + label + '─' * (width-2-len(label)) + '╮'
    def row(label): return '│ ' + clean(label)[:inner].ljust(inner) + ' │'
    wrapped = []
    for detail in details:
        wrapped.extend(textwrap.wrap(clean(detail), width=inner) or [''])
    # List and About each keep a visible viewport on small terminals.
    budget = max(2, height - 8 - len(footer_lines) - len(navigation))
    about_room = min(len(wrapped), max(1, budget // 2), 9)
    room = max(1, budget - about_room)
    room = min(room, max(1, len(rows)), 12)
    lines = [clean(title)[:width], border('Profile' if title == 'Profiles' else 'Select')]
    start = max(0, selected - room + 1)
    visible = rows[start:start + room]
    lines.extend(row(('› ' if start + i == selected else '  ') + item[0]) for i, item in enumerate(visible))
    lines += ['╰' + '─' * (width-2) + '╯', '', border('About')]
    offset = max(0, min(detail_offset, len(wrapped) - about_room))
    lines.extend(row(line) for line in wrapped[offset:offset+about_room])
    lines += ['╰' + '─' * (width-2) + '╯', *footer_lines, *navigation]
    return '\n'.join(line[:width] for line in lines[:height])


def show(value):
    if sys.stdout.isatty() and os.environ.get('TERM') != 'dumb' and not os.environ.get('NO_COLOR'):
        value = '\n'.join(('\033[1;36m' + line + '\033[0m') if line.startswith('│ › ') else line for line in value.splitlines())
    sys.stdout.write('\033[H\033[2J' + value + '\n'); sys.stdout.flush()


def choose(title, rows, detail=lambda item: [], actions='', selected=0):
    """Return (key, value). Rows are labels and opaque values; no side effects."""
    if not rows:
        rows = [('No entries yet', None)]
    selected = min(max(0, selected), len(rows) - 1)
    detail_offset = 0
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print(title)
        for index, (label, _) in enumerate(rows, 1): print(f'{index}. {label}')
        from setup_prompts import prompt
        answer = prompt('Number, action, or B Back: ').lower()
        if answer.isdigit() and 1 <= int(answer) <= len(rows): return 'enter', rows[int(answer)-1][1]
        return answer, rows[0][1]
    with keyboard():
        while True:
            show(frame(title, rows, selected, detail(rows[selected][1]), actions, detail_offset=detail_offset))
            value = key()
            if value in ('up', 'k'): selected = (selected - 1) % len(rows); detail_offset = 0
            elif value in ('down', 'j'): selected = (selected + 1) % len(rows); detail_offset = 0
            elif value == 'pageup': detail_offset = max(0, detail_offset - 4)
            elif value == 'pagedown': detail_offset += 4
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
