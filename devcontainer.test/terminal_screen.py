"""Minimal visible-screen reader for the setup TUI's cursor-addressed updates."""
import re


def terminal_screen(transcript):
    rows = {}; row = column = 0
    for match in re.finditer(r'\x1b\[([0-?]*)([ -/]*)([@-~])|([^\x1b]+)', transcript.decode(errors='replace')):
        parameters, _, command, text = match.groups()
        if text is not None:
            for character in text:
                if character == '\r': column = 0
                elif character == '\n': row += 1
                elif character == '\b': column = max(0, column - 1)
                elif character >= ' ':
                    line = rows.setdefault(row, [])
                    line.extend(' ' for _ in range(column + 1 - len(line)))
                    line[column] = character; column += 1
        elif command in ('H', 'f'):
            positions = parameters.split(';')
            row = int(positions[0] or 1) - 1
            column = int(positions[1] or 1) - 1 if len(positions) > 1 else 0
        elif command == 'J' and parameters == '2': rows = {}
        elif command == 'K': rows[row] = rows.get(row, [])[:column]
    return '\n'.join(''.join(rows.get(index, [])) for index in range(max(rows, default=0) + 1))
