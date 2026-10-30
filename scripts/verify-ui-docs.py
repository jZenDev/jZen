#!/usr/bin/env python3
"""Check public zen_ui_widgets widget classes have a guide entry and Dart example."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = Path('client/zen_ui_widgets')
EXPORT = re.compile(r"export\s+'([^']+)'(?:\s+show\s+([^;]+))?\s*;", re.S)
WIDGET = re.compile(r'\bclass\s+(\w+)(?:\s*<[^>{}]+>)?\s+extends\s+(?:StatelessWidget|StatefulWidget|FormField(?:<[^>]+>)?)\b')


def check(root: Path) -> list[str]:
    package = root / PACKAGE
    entry = package / 'lib/zen_ui_widgets.dart'
    guide = package / 'README.md'
    try:
        exports = entry.read_text(encoding='utf-8')
        documentation = guide.read_text(encoding='utf-8')
        widgets = set()
        for path, shown in EXPORT.findall(exports):
            # Generated localization libraries contain delegates, not widget declarations,
            # and are deliberately absent in a clean checkout.
            if path.startswith('src/l10n/generated/'):
                continue
            source = (entry.parent / path).read_text(encoding='utf-8')
            names = set(WIDGET.findall(source))
            if shown:
                names &= set(re.findall(r'\b\w+\b', shown))
            widgets.update(name for name in names if not name.startswith('_'))
    except OSError as exc:
        return [f'Cannot inspect UI exports or guide: {exc}']
    if not widgets:
        return ['No public widgets found; check the export parser and package path.']
    errors = []
    for name in sorted(widgets):
        section = re.search(
            r'^#{2,6}\s+`?' + re.escape(name) + r'`?(?:[ \t][^\n]*)?\n(.*?)(?=^#{1,6}\s|\Z)',
            documentation, re.M | re.S,
        )
        if not section:
            errors.append(f'{name}: missing dedicated guide heading')
            continue
        content = section.group(1)
        prose = re.sub(r'```.*?```', '', content, flags=re.S).strip()
        if not prose:
            errors.append(f'{name}: missing explanation')
        blocks = re.findall(r'```dart\s*\n(.*?)```', content, re.S)
        if not any(re.search(r'\b' + re.escape(name) + r'(?:<[^\n>]+>)?(?:\.\w+)?\s*\(', block) for block in blocks):
            errors.append(f'{name}: missing Dart usage example in its section')
    return errors


def main() -> int:
    errors = check(ROOT)
    if errors:
        print('UI documentation is incomplete:\n' + '\n'.join(f'  {e}' for e in errors), file=sys.stderr)
        return 1
    print('Public UI widgets have guide entries and Dart examples.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
