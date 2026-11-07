#!/usr/bin/env python3
"""Builds each package of Downloads/Header Versions/ in a scratch copy and runs its demo.
Prints PASS / FAIL / SKIP per language. A package passes when the demo's output equals expected.txt.
    python3 tools/test_header_versions.py [language-folder ...]
"""
import json, os, shutil, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Downloads', 'Header Versions'); SRC = os.path.join(ROOT, 'bindings')
expected = open(os.path.join(SRC, '_common', 'expected.txt')).read().strip()
want = set(sys.argv[1:]); results = []
for slug in sorted(os.listdir(SRC)):
    mp = os.path.join(SRC, slug, 'meta.json')
    if slug.startswith('_') or not os.path.exists(mp): continue
    meta = json.load(open(mp))
    if want and meta['folder'] not in want: continue
    src = os.path.join(OUT, meta['folder'])
    with tempfile.TemporaryDirectory() as tmp:
        work = os.path.join(tmp, meta['folder']); shutil.copytree(src, work)
        env = dict(os.environ, LD_LIBRARY_PATH=work)
        def run(cmd, t=600):
            return subprocess.run(cmd, shell=True, cwd=work, env=env, capture_output=True, text=True, timeout=t)
        r = run('./build.sh')
        if r.returncode: results.append((meta['name'], 'FAIL', 'build.sh: ' + r.stderr.strip()[:200])); continue
        bad = None
        for s in meta.get('setup', []):
            r = run(s)
            if r.returncode: bad = f"setup '{s}': " + (r.stderr or r.stdout).strip()[-300:]; break
        if bad: results.append((meta['name'], 'SKIP' if 'network' in bad.lower() else 'FAIL', bad)); continue
        r = run(meta['run'])
        out = r.stdout.strip()
        if r.returncode == 0 and out == expected: results.append((meta['name'], 'PASS', ''))
        else: results.append((meta['name'], 'FAIL', f"rc={r.returncode} out={out[:150]!r} err={r.stderr.strip()[-250:]!r}"))
for n, s, d in results: print(f'{s:5s} {n:12s} {d}')
print(f"\n{sum(1 for r in results if r[1]=='PASS')} passed, {sum(1 for r in results if r[1]=='FAIL')} failed, {sum(1 for r in results if r[1]=='SKIP')} skipped")
sys.exit(1 if any(r[1] == 'FAIL' for r in results) else 0)
