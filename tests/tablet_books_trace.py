"""Read the latest observed Books state/visible targets, never stale geometry."""
import json
import re
import sys

def latest(text):
    text = re.sub(r'\x1b\[[0-9;]*m', '', text)
    matches = list(re.finditer(r'PaperBooks state (\{[^\n]*)', text))
    if not matches: raise ValueError('No Books state observed')
    match = matches[-1]
    state, _ = json.JSONDecoder().raw_decode(match.group(1))
    targets = {}
    for row in text[match.end():].splitlines():
        target = re.search(r'PaperBooks target (\S+) (\d+) (\d+) (true|false)', row)
        if target and target[4] == 'true': targets[target[1]] = (int(target[2]), int(target[3]))
    return state, targets

def main():
    state, targets = latest(sys.stdin.read())
    action, name = sys.argv[1:3]
    if action == 'state': print(state[name])
    elif action == 'target': print(*targets[name])
    elif action == 'unsaved-result':
        saved = set(name.split(','))
        print(next(key for key in targets if key.startswith('booksResult_') and key[len('booksResult_'):] not in saved))
    else: raise ValueError('Unknown observation request')

if __name__ == '__main__': main()
