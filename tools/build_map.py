#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Narzędzie do budowy mapy zależności EA (MQL5):
- skanuje .mqh/.mq5 w podanym folderze
- wyciąga include'y, definicje funkcji, wywołania, globalne/input/extern
- tworzy EA_map.yaml i callgraph.dot

Uwaga: heurystyki oparte na regexach (C++-like). Dostosowane do stylu EA.
"""

import os, re, argparse, sys, json
from collections import defaultdict, OrderedDict

RE_INCLUDE = re.compile(r'^\s*#include\s*[<"]([^">]+)[">]', re.M)
RE_INPUT   = re.compile(r'^\s*input\s+([A-Za-z_][\w:<>\*\[\]\s]+)\s+([A-Za-z_]\w*)', re.M)
RE_EXTERN  = re.compile(r'^\s*extern\s+([A-Za-z_][\w:<>\*\[\]\s]+)\s+([A-Za-z_]\w*)', re.M)
RE_GLOBAL  = re.compile(r'^\s*(?!input\b)(?!extern\b)(?:static\s+)?(?!return\b)([A-Za-z_][\w:<>\*\[\]\s]+)\s+([A-Za-z_]\w*)\s*(?:=|;|\[)', re.M)

RE_FUNC_DEF = re.compile(
    r'^(?P<ret>[A-Za-z_][\w:<>\*\s&]+?)\s+(?P<name>[A-Za-z_]\w*)\s*\((?P<args>[^)]*)\)\s*(?:const\s*)?\{',
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

def iter_files(root):
    for base, _, files in os.walk(root):
        for f in files:
            if f.lower().endswith(('.mqh', '.mq5')):
                yield os.path.join(base, f)

def load_text(path):
    with open(path, 'r', encoding='utf-8', errors='ignore') as fh:
        return fh.read()

def sanitize_type(t):
    return ' '.join(t.split())

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True, help='Folder źródłowy (np. MQL5/Include/StartTester)')
    ap.add_argument('--out', required=True, help='Ścieżka wyjściowa YAML (np. docs/deps/EA_map.yaml)')
    ap.add_argument('--dot', required=False, help='(opcjonalnie) callgraph DOT')
    args = ap.parse_args()

    files = list(iter_files(args.src))
    if not files:
        print('Brak plików do analizy.', file=sys.stderr)
        sys.exit(1)

    all_funcs = set()
    file_funcs = defaultdict(list)
    file_text = {}

    for p in files:
        txt = load_text(p)
        file_text[p] = txt
        for m in RE_FUNC_DEF.finditer(txt):
            name = m.group('name')
            if not RE_BAD_NAMES.match(name):
                all_funcs.add(name)
                file_funcs[p].append((name, m.start(), m.end()))

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

        for inc in RE_INCLUDE.findall(txt):
            node['includes'][inc] = {'provides': []}

        for t, r in [('input', RE_INPUT), ('extern', RE_EXTERN), ('global', RE_GLOBAL)]:
            for m in r.finditer(txt):
                typ, name = sanitize_type(m.group(1)), m.group(2)
                g = node['globals'].setdefault(name, {'type': typ, 'owner': rel, 'origin': set(), 'used_by': [], 'purpose': ''})
                g['origin'].add(t)

        for m in RE_FUNC_DEF.finditer(txt):
            name = m.group('name')
            if RE_BAD_NAMES.match(name): 
                continue
            start = m.end()
            body = []
            depth = 1
            i = start
            while i < len(txt) and depth > 0:
                ch = txt[i]
                body.append(ch)
                if ch == '{': depth += 1
                elif ch == '}': depth -= 1
                i += 1
            body = ''.join(body[:-1]) if depth==0 and body else ''

            sig = f"{sanitize_type(m.group('ret'))} {name}({m.group('args').strip()})"
            fnode = OrderedDict()
            fnode['signature'] = sig
            fnode['purpose'] = ''
            fnode['calls'] = []
            fnode['reads'] = []
            fnode['writes'] = []
            fnode['file_scope'] = rel
            fnode['entrypoint'] = name in ('OnInit','OnTick','OnDeinit')

            for fname in all_funcs:
                if fname == name: 
                    continue
                if call_pattern(fname).search(body):
                    fnode['calls'].append(fname)
                    dot_edges.add((name, fname, rel))

            globs = list(node['globals'].keys())
            for gname in globs:
                if is_write(gname, body):
                    fnode['writes'].append(gname)
                elif is_read(gname, body):
                    fnode['reads'].append(gname)

            node['functions'][name] = fnode

        for gname, g in node['globals'].items():
            g['origin'] = sorted(list(g['origin']))

        data[rel] = node

    for rel, node in data.items():
        for fname, fnode in node['functions'].items():
            for g in fnode.get('reads',[])+fnode.get('writes',[]):
                if g in node['globals']:
                    node['globals'][g]['used_by'].append(fname)
                else:
                    for rel2, node2 in data.items():
                        if g in node2['globals']:
                            node2['globals'][g]['used_by'].append(f"{rel}:{fname}")
                            break

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
            fh.write('digraph callgraph {\n')
            fh.write('  rankdir=LR;\n  node [shape=box, fontsize=10];\n')
            for (src, dst, rel) in sorted(dot_edges):
                fh.write(f'  "{src}" -> "{dst}" [label="{rel}"];\n')
            fh.write('}\n')

    print(f"OK: zapisano {args.out}" + (f" i {args.dot}" if args.dot else ""))

if __name__ == '__main__':
    main()
