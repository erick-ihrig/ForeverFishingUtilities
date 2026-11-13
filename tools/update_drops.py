#!/usr/bin/env python3
"""Check the catch-rate source for changes and rebuild Drops.lua when needed.

Source: the cMaNGOS Classic database, https://github.com/cmangos/classic-db

    python3 tools/update_drops.py           check; rebuild only if the source changed
    python3 tools/update_drops.py --force   rebuild even if nothing changed

The check is one tiny request (git ls-remote). Only when the source's latest
commit differs from the one recorded in tools/drops_source.json does it look
closer, and only when the database dump itself changed does it download it
(about 13 MB). Needs git and Python 3; nothing else.

Exit codes: 0 nothing to do, 10 Drops.lua was rewritten, 11 needs a human look
(a new upstream update file touches fishing data, or an area has no name).
"""
import collections, gzip, json, os, re, subprocess, sys, tempfile

REPO = "https://github.com/cmangos/classic-db"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STATE = os.path.join(HERE, "drops_source.json")
AREAS = os.path.join(HERE, "areas.json")
OUT = os.path.join(ROOT, "Drops.lua")
SEASONAL_REF = 13755                      # Winter Squid / Raw Summer Bass roll
SEASON_TAG = {322: "w", 323: "s"}         # condition id -> tag
FISHING_WORDS = re.compile(
    r"fishing_loot_template|skill_fishing_base_level|"
    r"reference_loot_template[^;]*\b(110\d\d|13755)\b", re.S)


def git(*args, cwd=None, text=True):
    return subprocess.run(["git", *args], cwd=cwd, check=True, text=text,
                          capture_output=True).stdout


def sql_rows(src, table):
    """All value tuples of a table's INSERT statements, as lists of strings."""
    out = []
    for m in re.finditer(r"INSERT INTO `%s` VALUES (.*?);\n" % table, src, re.S):
        s, i, n = m.group(1), 0, len(m.group(1))
        while i < n:
            if s[i] != "(":
                i += 1
                continue
            i += 1
            row, cur, quoted = [], "", False
            while True:
                c = s[i]
                if quoted:
                    if c == "\\":
                        cur += s[i + 1]; i += 2; continue
                    if c == "'":
                        quoted = False; i += 1; continue
                    cur += c; i += 1; continue
                if c == "'":
                    quoted = True
                elif c == ",":
                    row.append(cur); cur = ""
                elif c == ")":
                    row.append(cur); i += 1; break
                else:
                    cur += c
                i += 1
            out.append(row)
    return out


def build(sql_text):
    """Returns (Drops.lua text, list of problems)."""
    areas = {int(k): v for k, v in json.load(open(AREAS, encoding="utf8")).items()}
    name = {k: v[0] for k, v in areas.items()}
    parent = {k: v[1] for k, v in areas.items() if v[1]}
    problems = []

    by = collections.defaultdict(list)
    for r in sql_rows(sql_text, "fishing_loot_template"):
        by[int(r[0])].append(r)
    ref = collections.defaultdict(list)
    for r in sql_rows(sql_text, "reference_loot_template"):
        ref[int(r[0])].append(r)
    if len(by) < 50:
        raise SystemExit("Parsed too few fishing rows; the dump's format may have changed.")

    def is_base(r):
        return int(r[4]) < 0 and -int(r[4]) != SEASONAL_REF

    def has_base(e):
        return any(is_base(r) for r in by[e])

    # The dump leaves some areas without the table its own comments assign them.
    base_rows = {}
    for r in [r for rs in by.values() for r in rs]:
        if is_base(r):
            base_rows[-int(r[4])] = r
    for r in base_rows.values():
        for i in {int(x) for x in re.findall(r"\((\d+)\)", r[7])}:
            if i in by and not has_base(i):
                if i == 357:      # Feralas: stray catfish rows; the comment's table fits a 205 zone
                    by[i] = []
                by[i].append([str(i)] + r[1:])
    # What's still without a table takes its zone's.
    for e in list(by):
        if e and not has_base(e) and parent.get(e) in by:
            by[e] += [r for r in by[parent[e]] if is_base(r)]

    def expand(rows, scale=1.0):
        out, groups = [], collections.defaultdict(list)
        for r in rows:
            item, ch, g, mref, cond = int(r[1]), float(r[2]), int(r[3]), int(r[4]), int(r[6])
            if mref < 0:
                sub = expand(ref[-mref], scale * abs(ch) / 100.0)
                if g == 0:
                    out.extend(sub)
                else:
                    groups[g].append(("ref", sub, ch))
                continue
            tag = "q" if ch < 0 else SEASON_TAG.get(cond, "")
            if g == 0 or ch < 0:
                out.append((item, abs(ch) * scale, tag))
            else:
                groups[g].append(("item", item, ch, tag))
        for rs in groups.values():
            items = [x for x in rs if x[0] == "item"]
            refs = [x for x in rs if x[0] == "ref"]
            zeros = [x for x in items if x[2] == 0]
            # Items listed at 0 share what the others leave of 100%.
            rest = max(0, 100 - sum(x[2] for x in items) - sum(x[2] for x in refs))
            for x in refs:
                out.extend(x[1])
            for x in items:
                out.append((x[1], (x[2] if x[2] > 0 else rest / len(zeros)) * scale, x[3]))
        return out

    tables, area_table = {}, {}
    for e, rs in sorted(by.items()):
        if e == 0:
            continue
        if e not in name:
            problems.append("area %d has fishing data but no name in tools/areas.json" % e)
            continue
        merged = collections.OrderedDict()
        for item, pct, tag in expand(rs):
            merged[(item, tag)] = merged.get((item, tag), 0) + pct
        rows = tuple(sorted(((i, round(p, 2), t) for (i, t), p in merged.items()),
                            key=lambda x: (x[2] == "q", -x[1], x[0])))
        tables.setdefault(rows, len(tables) + 1)
        area_table[e] = tables[rows]

    def q(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    L = ["-- Open-water fishing catches by zone and subzone.",
         "-- Source: the cMaNGOS Classic database (github.com/cmangos/classic-db), tables",
         "-- fishing_loot_template and reference_loot_template.",
         "-- Generated by tools/update_drops.py; don't edit by hand.",
         "-- Each row: { itemID, percent, tag }. Tags: \"w\" winter only, \"s\" summer only,",
         "-- \"q\" only while on the item's quest. Percentages are per successful catch.",
         "", "local _, ns = ...", "", "ns.DROP_TABLES = {"]
    for rows, i in tables.items():
        L.append("    [%d] = { %s }," % (i, ", ".join(
            "{%d,%g%s}" % (item, pct, ',"%s"' % tag if tag else "") for item, pct, tag in rows)))
    L += ["}", "", "-- Zone (or dungeon) name -> table.", "ns.DROP_ZONES = {"]
    for e in sorted((e for e in area_table if e not in parent), key=lambda e: name[e]):
        L.append("    [%s] = %d," % (q(name[e]), area_table[e]))
    L += ["}", "", "-- Subzones whose catches differ from their zone: [zone][subzone] -> table.",
          "ns.DROP_SUBZONES = {"]
    subs = collections.defaultdict(list)
    for e in area_table:
        p = parent.get(e)
        if p and area_table.get(p) != area_table[e]:
            subs[name[p]].append(e)
    for zone in sorted(subs):
        L.append("    [%s] = {" % q(zone))
        for e in sorted(subs[zone], key=lambda e: name[e]):
            L.append("        [%s] = %d," % (q(name[e]), area_table[e]))
        L.append("    },")
    L += ["}", ""]
    return "\n".join(L), problems


def main():
    force = "--force" in sys.argv
    state = json.load(open(STATE)) if os.path.exists(STATE) else {}

    head = git("ls-remote", REPO, "HEAD").split()[0]
    if head == state.get("head") and not force:
        print("Up to date: the source hasn't changed since the last check (%s)." % head[:10])
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        # History-free, file-free clone: a few hundred KB. Files are fetched one by one below.
        git("clone", "-q", "--depth", "1", "--filter=blob:none", "--no-checkout", REPO, tmp)
        dump_tree = git("rev-parse", "HEAD:Full_DB", cwd=tmp).strip()

        # Update files added since last time that mention fishing data.
        flagged = []
        if state.get("head"):
            try:
                git("fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", state["head"], cwd=tmp)
                changed = git("diff", "--name-only", state["head"], "HEAD", "--", "Updates", cwd=tmp).split("\n")
            except subprocess.CalledProcessError:
                changed = []
                print("Couldn't compare against the last checked commit, so new update files weren't scanned.")
            for path in filter(None, changed):
                try:
                    text = git("show", "HEAD:" + path, cwd=tmp)
                except (subprocess.CalledProcessError, UnicodeDecodeError):
                    continue
                if FISHING_WORDS.search(text):
                    flagged.append(path)

        result = 0
        if dump_tree != state.get("dump_tree") or force:
            dump = [p for p in git("ls-tree", "--name-only", "HEAD", "Full_DB/", cwd=tmp).split("\n")
                    if p.endswith(".sql.gz")]
            if len(dump) != 1:
                raise SystemExit("Expected one .sql.gz in Full_DB, found: %s" % dump)
            raw = git("show", "HEAD:" + dump[0], cwd=tmp, text=False)
            text, problems = build(gzip.decompress(raw).decode("utf8", "replace"))
            old = open(OUT, encoding="utf8").read() if os.path.exists(OUT) else ""
            if text != old:
                with open(OUT, "w", encoding="utf8", newline="\n") as f:
                    f.write(text)
                print("Drops.lua rewritten from %s. Review with: git diff Drops.lua" % dump[0])
                result = 10
            else:
                print("The database dump changed (%s), but the fishing data in it didn't." % dump[0])
            for p in problems:
                print("NEEDS A LOOK: " + p)
                result = 11
        else:
            print("The source has new commits, but its database dump is unchanged.")

        if flagged:
            print("NEEDS A LOOK: these new upstream update files mention fishing data and")
            print("aren't in the dump yet (%s/blob/master/<path>):" % REPO)
            for path in flagged:
                print("  " + path)
            result = 11

    json.dump({"repo": REPO, "head": head, "dump_tree": dump_tree}, open(STATE, "w"), indent=2)
    open(STATE, "a").write("\n")
    return result


if __name__ == "__main__":
    sys.exit(main())
