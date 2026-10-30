#!/usr/bin/env python3
"""Block an agent stop when the public widget guide is incomplete."""
import importlib.util
import json
import sys
from pathlib import Path


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0
    if payload.get('stop_hook_active'):
        return 0
    script = Path(__file__).resolve().with_name('verify-ui-docs.py')
    spec = importlib.util.spec_from_file_location('verify_ui_docs', script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    errors = module.check(script.parent.parent)
    if errors:
        print('UI guide is incomplete; update client/zen_ui_widgets/README.md:\n' +
              '\n'.join(f'  {error}' for error in errors), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
