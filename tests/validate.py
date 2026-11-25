"""Lua 5.1 syntax check, TOC validation and mocked-client regressions.
Requires: pip install lupa==2.8   Run: python -X utf8 tests/validate.py
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval('function(s, n) local f, e = loadstring(s, n); return f ~= nil, e end')

count = 0
for p in sorted(ROOT.rglob('*.lua')):
    ok, err = compile_lua(p.read_text(encoding='utf-8'), str(p.relative_to(ROOT)))
    assert ok, err
    count += 1
print(f'PASS: {count} Lua files compile under Lua 5.1')

toc = [l.strip() for l in (ROOT / 'VoidMarkHealer.toc').read_text().splitlines()]
assert any(l.startswith('## Interface: 16001') for l in toc), 'Interface must be 16001'
files = [l.replace('\\', '/') for l in toc if l and not l.startswith('#')]
for f in files:
    assert (ROOT / f).exists(), f'missing {f}'
addon_lua = {p.name for p in ROOT.glob('*.lua')}
assert addon_lua == set(files), f'TOC/file mismatch: {addon_lua ^ set(files)}'
print(f'PASS: TOC lists {len(files)} files, all present')

g = lua.globals()
g.ROOT = str(ROOT)
g.TOC_FILES = lua.table_from(files)
lua.execute((ROOT / 'tests' / 'mock.lua').read_text(encoding='utf-8'))
lua.execute((ROOT / 'tests' / 'regressions.lua').read_text(encoding='utf-8'))
print('PASS: mocked client regressions')
