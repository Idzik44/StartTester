#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Budowa mapy zależności dla MQL5 (działa z plikami UTF-16/UTF-8/CP1250).
- Zbiera include'y, funkcje, wywołania, (input/extern/global) i użycia globali.
- Tworzy YAML i (opcjonalnie) callgraph DOT.
"""

import os, re, argparse, sys, json
from collections import defaultdict, OrderedDict

# ── Regexy ─────────────────────────────────────────────────────────
RE_INCLUDE = re.compile(r'^\s*#include\s*[<"]([^">]+)[">]', re.M)
RE_INPUT   = re.compile(r'^\s*input\s+([A-Za-z_][\w:<>\*\[\]\s]+)\s+([A-Za-z_]\w*)', re.M)
RE_EXTERN  = re.compile(r'^\s*extern\s+([A-Za-z_][\w:<>\*\[\]\s]+)\s+([A-Za-z_]\w*)', re.M)
RE_GLOBAL  = re.compile(r'^\s*(?!input\b)(?!extern\b)(?:static\s+)?(?!return\b)([A-Za-z_][\w:<>\*\[\]\s]+)\s+([A-Za-z_]\w*)\s*(?:=|;|\[)', re.M)

# Funkcja w stylu: "int OnInit()" lub "void Foo(int a)\n{"
RE_FUNC_DEF = re.compile(
    r'^\s*(?P<ret>[A-Za-z_][\w:<>\*\s&]+?)\s+(?P<name>[A-Za-z_]\w*)\s*\((?P<args>[^)]*)\)\s*(?:const\s*)?\s*\{',
    re.M
)
RE_BAD_NAMES = re.compile(r'^(if|for|while|switch|return|else)$')

def call_pattern(name):
    return re.compile(r'(?<![A-Za-z_])' + re.escape(name) + r'\s*\(', re.M)

def is_write(var, body):
    pat_assign = re.compile(r'(?<![A-Za-z_])' + re.escape(var) + r'\s*(?:\+\+|--|[\+\-\*/%&\|\^]?=)')
    return bool(pat_assign.search(body))

def is_read(var, body):
    pat_word = re.compile(r'(?<![A-Za-z_])' + re.escape(var) + r'(?![A-Za-z_])')
    return bool(pat_word.search(body))

# ── IO z auto-wykrywaniem kodowania ───────────────────────────────
def load_text(path):
    """
    Czyta binarnie i próbuje kilku kodowań:
    - jeżeli wykryje BOM UTF-16 lub NULL-e → próbuje UTF-16/LE/BE najpierw
    - w przeciwnym razie UTF-8-SIG/UTF-8, a potem CP1250/Latin-1
    """
    with open(path, 'rb') as fh:
        data = fh.read()

    looks_utf16 = data.startswith(b'\xff\xfe') or data.startswith(b'\xfe\xff') or (b'\x00' in data[:400])

    encs = []
    if looks_utf16:
        encs = ['utf-16', 'utf-16-le', 'utf-16-be', 'utf-8-sig', 'cp1250', 'latin-1']
    else:
        encs = ['utf-8-sig', 'utf-8', 'cp1250', 'latin-1', 'utf-16', 'utf-16-le', 'utf-16-be']

    for enc in encs:
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue

    # awaryjnie: „cokolwiek się da”
    return data.decode('utf-8', errors='ignore')

def sanitize_type(t):
    return ' '.join(t.split())

# ── Main ───────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True, help='Folder źródłowy (np. MQL5 lub MQL5/Include/StartTester)')
    ap.add_argument('--out', required=True, help='Wyjściowy YAML (np. docs/deps/EA_map.yaml)')
    ap.add_argument('--dot', help='Opcjonalny plik grafu DOT (np. docs/deps/callgraph.dot)')
    ap.add_argument('--verbose', action='store_true', help='Wypisuje statystyki parsowania')
    args = ap.parse_args()

    # Zbierz pliki
    files = []
    for base, _, fnames in os.walk(args.src):
        for f in fnames:
            if f.lower().endswith(('.mqh', '.mq5')):
                files.append(os.path.join(base, f))
    if not files:
        print('Brak plików do analizy.', file=sys.stderr)
        sys.exit(1)

    # 1. Skan nazw funkcji globalnie (żeby wiedzieć, czego szukać w „calls”)
    all_funcs = set()
    file_text = {}
    func_blocks = defaultdict(list)  # path → [ (name, sig, body_start, body) ]

    for p in files:
        txt = load_text(p)
        file_text[p] = txt
        count_here = 0
        for m in RE_FUNC_DEF.finditer(txt):
            name = m.group('name')
            if RE_BAD_NAMES.match(name):
                continue
            # wyciągnij ciało { ... }
            start = m.end()
            depth = 1
            i = start
            L = len(txt)
            while i < L and depth > 0:
                ch = txt[i]
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                i += 1
            body = txt[start:i-1] if depth == 0 else ''
            sig = f"{sanitize_type(m.group('ret'))} {name}({m.group('args').strip()})"
            func_blocks[p].append((name, sig, start, body))
            all_funcs.add(name)
            count_here += 1
        if args.verbose:
            rel = os.path.relpath(p).replace('\\','/')
            print(f"[scan] {rel} -> funkcji: {count_here}")

    # 2. Budowa struktury danych per plik
    data = OrderedDict()
    dot_edges = set()

    for p in files:
        txt = file_text[p]
        rel = os.path.relpath(p).replace('\\','/')
        node = OrderedDict()
        node['role'] = ''
        node['includes'] = OrderedDict()
        node['globals'] = OrderedDict()
        node['functions'] = OrderedDict()

        # includes
        for inc in RE_INCLUDE.findall(txt):
            node['includes'][inc] = {'provides': []}

        # input/extern/global (lokalne deklaracje)
        for tag, regex in [('input', RE_INPUT), ('extern', RE_EXTERN), ('global', RE_GLOBAL)]:
            for m in regex.finditer(txt):
                typ, name = sanitize_type(m.group(1)), m.group(2)
                g = node['globals'].setdefault(name, {'type': typ, 'owner': rel, 'origin': set(), 'used_by': [], 'purpose': ''})
                g['origin'].add(tag)

        # funkcje
        for (name, sig, _, body) in func_blocks[p]:
            fnode = OrderedDict()
            fnode['signature'] = sig
            fnode['purpose'] = ''
            fnode['calls'] = []
            fnode['reads'] = []
            fnode['writes'] = []
            fnode['file_scope'] = rel
            fnode['entrypoint'] = name in ('OnInit','OnTick','OnDeinit')

            # calls
            for fname in all_funcs:
                if fname == name:
                    continue
                if call_pattern(fname).search(body):
                    fnode['calls'].append(fname)
                    dot_edges.add((name, fname, rel))

            # reads/writes (tylko te globalne zidentyfikowane w tym pliku na razie)
            for gname in node['globals'].keys():
                if is_write(gname, body):
                    fnode['writes'].append(gname)
                elif is_read(gname, body):
                    fnode['reads'].append(gname)

            node['functions'][name] = fnode

        # finalize globals origin
        for gname, g in node['globals'].items():
            g['origin'] = sorted(list(g['origin']))

        data[rel] = node

    # 3. Rozszerz used_by dla globali znalezionych w INNYCH plikach
    #    (jeśli funkcja czyta/zapisuje nazwę globalną, a global jest zdefiniowany gdzie indziej)
    for rel, node in data.items():
        for fname, fnode in node['functions'].items():
            for g in fnode.get('reads', []) + fnode.get('writes', []):
                if g in node['globals']:
                    node['globals'][g]['used_by'].append(fname)
                else:
                    for rel2, node2 in data.items():
                        if g in node2['globals']:
                            node2['globals'][g]['used_by'].append(f"{rel}:{fname}")
                            break

    # 4. Kandydaci do usunięcia (funkcje nigdzie nie wołane; nie dotyczy entrypointów)
    all_calls = set()
    for rel, node in data.items():
        for f, fn in node['functions'].items():
            for c in fn['calls']:
                all_calls.add(c)
    unused_funcs = []
    for rel, node in data.items():
        for f, fn in node['functions'].items():
            if fn['entrypoint']:
                continue
            if f not in all_calls:
                unused_funcs.append(f"{rel}:{f}")

    # Globalne bez użycia
    unused_globals = []
    for rel, node in data.items():
        for g, gn in node['globals'].items():
            if not gn['used_by']:
                unused_globals.append(f"{rel}:{g}")

    data['_summary'] = {
        'unused_candidates': {
            'functions': sorted(unused_funcs),
            'globals': sorted(unused_globals),
        }
    }

    # 5. Zapis YAML bez zależności
    def to_yaml(obj, indent=0):
        sp = '  ' * indent
        if isinstance(obj, dict):
            out = []
            for k,v in obj.items():
                if isinstance(v, (dict, list)):
                    out.append(f"{sp}{k}:")
                    out.append(to_yaml(v, indent+1))
                else:
                    if isinstance(v, set): v = list(v)
                    if isinstance(v, str):
                        out.append(f"{sp}{k}: {v}")
                    else:
                        out.append(f"{sp}{k}: {json.dumps(v, ensure_ascii=False)}")
            return '\n'.join(out)
        elif isinstance(obj, list):
            out = []
            for it in obj:
                if isinstance(it, (dict, list)):
                    out.append(f"{sp}-")
                    out.append(to_yaml(it, indent+1))
                else:
                    out.append(f"{sp}- {json.dumps(it, ensure_ascii=False)}")
            return '\n'.join(out)
        else:
            return f"{sp}{json.dumps(obj, ensure_ascii=False)}"

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as fh:
        fh.write(to_yaml(data))
        fh.write('\n')

    if args.dot:
        os.makedirs(os.path.dirname(args.dot), exist_ok=True)
        with open(args.dot, 'w', encoding='utf-8') as fh:
            fh.write('digraph callgraph {\n  rankdir=LR;\n  node [shape=box, fontsize=10];\n')
            for (src, dst, rel) in sorted(dot_edges):
                fh.write(f'  "{src}" -> "{dst}" [label="{rel}"];\n')
            fh.write('}\n')

    if args.verbose:
        print(f"[done] files: {len(files)} | functions total: {sum(len(v) for v in func_blocks.values())}")

if __name__ == '__main__':
    main()
