"""Strip every player but the owner from a WoWCombatLog segment.

usage: python -I anonymise.py <in.txt> <out.txt> <owner GUID>

Every other player's GUID becomes Player-0-000000NN and its "Name-Realm-US"
becomes "PlayerNN-Realm". Pets and guardians carry their owner's GUID in the
advanced fields, so those GUIDs are rewritten too (same table). Nothing else
changes: timestamps, spells, amounts, creatures, positions are untouched. The
script then re-scans its own output for any original name or GUID and refuses
to finish if one is left.
"""
import io, re, sys, hashlib

src, dst, owner = sys.argv[1], sys.argv[2], sys.argv[3]
text = io.open(src, encoding="utf-8", newline="").read()

pairs = re.findall(r'(Player-\d+-[0-9A-F]+),"([^"]+)"', text)
guids = {}
names = {}
order = []
for guid, name in pairs:
    if guid == owner:
        continue
    if guid not in guids:
        order.append(guid)
        guids[guid] = None
    names.setdefault(guid, set()).add(name)
for n, guid in enumerate(sorted(order), 1):
    guids[guid] = "Player-0-%08d" % n
# Any player GUID that only ever appears bare (an advanced-field owner GUID, a target
# with no name field) still gets a pseudonym.
for guid in sorted(set(re.findall(r'Player-\d+-[0-9A-F]+', text))):
    if guid != owner and guid not in guids:
        order.append(guid)
        guids[guid] = "Player-0-%08d" % len(order)

name_map = {}
for guid, ns in names.items():
    for name in ns:
        num = guids[guid][-8:].lstrip("0")
        name_map[name] = "Player%s-Realm" % num
        bare = name.split("-")[0]
        name_map.setdefault(bare, "Player%s" % num)

out = text
for guid, pseudo in guids.items():
    out = out.replace(guid, pseudo)
# Longest names first so "Name-Realm-US" is replaced before the bare "Name".
for name in sorted(name_map, key=len, reverse=True):
    out = out.replace('"%s"' % name, '"%s"' % name_map[name])
# Bare names inside other quoted strings (a pet named after its owner, a spell text).
for name in sorted(name_map, key=len, reverse=True):
    if len(name) >= 4:
        out = out.replace(name, name_map[name])

leftover = [g for g in guids if g in out] + [n for n in name_map if n in out and len(n) >= 4]
if leftover:
    sys.exit("left in the output: %r" % leftover[:10])

io.open(dst, "w", encoding="utf-8", newline="").write(out)
print("players replaced:", len(guids), "names:", len(name_map))
print("lines in:", text.count("\n"), "lines out:", out.count("\n"))
print("owner events:", out.count(owner))
print("sha256 in :", hashlib.sha256(text.encode("utf-8")).hexdigest(), len(text.encode("utf-8")))
print("sha256 out:", hashlib.sha256(out.encode("utf-8")).hexdigest(), len(out.encode("utf-8")))
