#!/usr/bin/env python3
"""Offline test: loads the addon against mock.lua (stand-in WoW API) and runs test.lua.
Needs `pip install lupa`. Run from anywhere: python tools/test/run.py"""
import os, sys
import lupa.lua51 as lupa  # WoW runs Lua 5.1
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here)) + '/'
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(here, 'mock.lua'), encoding='utf8').read())
ns = lua.table()
files = [l.strip() for l in open(root + 'ForeverFishingUtilities.toc', encoding='utf8') if l.strip().endswith('.lua')]
load = lua.eval('function(src, name) return assert(loadstring(src, "@" .. name)) end')
for f in files:
    load(open(root + f, encoding='utf8').read(), f)('ForeverFishingUtilities', ns)
lua.execute(open(os.path.join(here, 'test.lua'), encoding='utf8').read())
out = list(lua.globals().LOG.values())
for l in out:
    print(l)
sys.exit(0 if out and out[-1] == 'ALL PASSED' else 1)
