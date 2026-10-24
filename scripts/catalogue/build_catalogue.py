#!/usr/bin/env python3
"""Build the bundled medicine catalogue (assets/catalogue/india.tsv.gz + aliases.tsv).

Inputs (download them yourself — see catalogue/README.md):
  --brands      CSV of Indian branded medicines (e.g. Kaggle "A-Z Medicine
                Dataset of India": name, price, Is_discontinued,
                manufacturer_name, type, pack_size_label,
                short_composition1, short_composition2).
  --janaushadhi CSV of the official Jan Aushadhi product list (Drug Code,
                Generic Name, Unit Size, MRP, Group Name). Optional.
  --schedule-h  CSV with a `salt` column: every entry of Schedule H of the
                Drugs Rules, 1945, copied from the official text. Without it
                nothing can be classified OTC — unlisted salts stay UNKNOWN.

Reference tables in catalogue/reference/ are always read: schedule_h1.csv,
schedule_x.csv, schedule_extra_strict.csv, salt_aliases.csv,
nil_rated_drugs.csv.

Rules:
  - Schedule comes only from official lists, per salt; the strictest salt
    wins (X > H1 > H > OTC). A salt that can't be resolved → UNKNOWN (Rule 11).
  - GST 5% for medicines (rate from 22-09-2025), 0% if every salt is on the
    nil-rated list.
  - MRP is integer paise (Rule 12), marked with the date it was observed.
  - Discontinued products are dropped.

  python3 scripts/catalogue/build_catalogue.py --brands az.csv \
      --janaushadhi ja.csv --schedule-h schedule_h.csv --out assets/catalogue
  python3 scripts/catalogue/build_catalogue.py --selftest
"""
import argparse
import csv
import gzip
import io
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF = os.path.join(ROOT, 'catalogue', 'reference')

# Salt-form words removed to get the active moiety ("Diclofenac Sodium" →
# "diclofenac") before schedule lookup. Schedules list the moiety and cover
# its salts.
SALT_FORMS = {
    'hydrochloride', 'hcl', 'hydrobromide', 'sodium', 'potassium', 'calcium',
    'magnesium', 'maleate', 'tartrate', 'bitartrate', 'citrate', 'sulphate',
    'sulfate', 'phosphate', 'acetate', 'succinate', 'fumarate', 'mesylate',
    'besylate', 'besilate', 'bromide', 'chloride', 'dihydrate', 'monohydrate',
    'trihydrate', 'anhydrous', 'proxetil', 'axetil', 'pivoxil', 'disodium',
    'dipropionate', 'propionate', 'valerate', 'furoate', 'butyrate',
    'hyclate', 'lactate', 'gluconate', 'malate', 'oxalate', 'nitrate',
    'trometamol', 'tromethamine', 'diethylamine', 'medoxomil', 'cilexetil',
    'ip', 'bp', 'usp', 'ph.eur', 'eq', 'equivalent', 'to', 'as',
}

PENICILLINS = {'amoxicillin', 'ampicillin', 'cloxacillin', 'dicloxacillin',
               'flucloxacillin', 'piperacillin', 'benzathine penicillin',
               'penicillin', 'phenoxymethylpenicillin', 'clavulanic acid',
               'sulbactam', 'tazobactam'}
ANTIBIOTIC_STEMS = ('cef', 'ceph', 'mycin', 'micin', 'floxacin', 'cycline',
                    'penem', 'azole', 'sulfa', 'co-trimoxazole', 'linezolid',
                    'vancomycin', 'colistin', 'nitrofurantoin', 'fosfomycin')

STRENGTH = re.compile(r'\(?\s*([\d.]+)\s*(mg|mcg|µg|g|iu|ml|%|w/w|w/v|units?)\s*\)?', re.I)


def norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9%+./ -]', ' ', (s or '').lower())).strip()


def load_csv(path):
    with open(path, newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))


class Reference:
    def __init__(self, schedule_h_path=None):
        self.alias = {}
        for r in load_csv(os.path.join(REF, 'salt_aliases.csv')):
            canon = norm(r['canonical'])
            self.alias[canon] = canon
            for a in r['aliases'].split('|'):
                if a.strip():
                    self.alias[norm(a)] = canon
        self.h1 = {self.canon(r['salt']) for r in load_csv(os.path.join(REF, 'schedule_h1.csv'))}
        self.x = {self.canon(r['salt']) for r in load_csv(os.path.join(REF, 'schedule_x.csv'))}
        self.extra = {self.canon(r['salt']): r['schedule'] for r in
                      load_csv(os.path.join(REF, 'schedule_extra_strict.csv'))}
        self.nil = {self.canon(r['salt']) for r in load_csv(os.path.join(REF, 'nil_rated_drugs.csv'))}
        self.seen = Counter()  # products per salt, filled by build()
        self._cache = {}
        self.h = None
        if schedule_h_path:
            self.h = {self.canon(r['salt']) for r in load_csv(schedule_h_path) if r.get('salt')}

    def canon(self, salt):
        s = norm(STRENGTH.sub(' ', salt or ''))
        if s in self.alias:
            return self.alias[s]
        words = [w for w in s.split() if w not in SALT_FORMS]
        s = ' '.join(words)
        return self.alias.get(s, s)

    def schedule_of(self, salt):
        c = self.canon(salt)
        if c not in self._cache:
            self._cache[c] = self._schedule(c)
        return self._cache[c]

    def _schedule(self, c):
        if not c:
            return 'UNKNOWN'
        if c in self.x:
            return 'X'
        if c in self.extra:
            return self.extra[c]
        if c in self.h1:
            return 'H1'
        if self.h is None:
            return 'UNKNOWN'
        if c in self.h:
            return 'H'
        # OTC only for a salt we have real evidence for: spelled like a
        # scheduled salt (likely a typo of one) or seen in too few products
        # → UNKNOWN, for the pharmacist to confirm.
        if self.near_scheduled(c) or self.seen.get(c, 0) < MIN_EVIDENCE:
            return 'UNKNOWN'
        return 'OTC'

    def near_scheduled(self, c):
        for s in self.x | self.h1 | set(self.extra) | (self.h or set()):
            if abs(len(s) - len(c)) <= 2 and edit_distance(s, c) <= 2:
                return True
        return False


MIN_EVIDENCE = 3  # products a salt must appear in before it can be OTC


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


RANK = {'OTC': 0, 'H': 1, 'H1': 2, 'X': 3, 'UNKNOWN': 4}


def classify(salts, ref):
    """Strictest schedule across salts. One X or H1 salt makes the whole
    product X / H1 even if another salt is unresolved (the X list is
    complete, so an unresolved salt can't be stricter than H1). Otherwise
    any unresolved salt → UNKNOWN."""
    if not salts:
        return 'UNKNOWN'
    found = [ref.schedule_of(s) for s in salts]
    if 'X' in found:
        return 'X'
    if 'H1' in found:
        return 'H1'
    if 'UNKNOWN' in found:
        return 'UNKNOWN'
    return max(found, key=RANK.get)


def split_composition(*parts):
    """'Amoxycillin (500mg) + Clavulanic Acid (125mg)' → [(salt, strength)]."""
    out = []
    for part in parts:
        for piece in re.split(r'\s*\+\s*', part or ''):
            piece = piece.strip()
            if not piece:
                continue
            m = STRENGTH.search(piece)
            strength = (m.group(1) + m.group(2).lower()) if m else ''
            name = STRENGTH.sub(' ', piece)
            name = re.sub(r'[()]', ' ', name)
            name = re.sub(r'\s+', ' ', name).strip()
            if name:
                out.append((name, strength))
    return out


def hsn_for(salts, ref):
    canon = [ref.canon(s) for s in salts]
    if any(c in PENICILLINS for c in canon):
        return '300410'
    if any(any(stem in c for stem in ANTIBIOTIC_STEMS) for c in canon):
        return '300420'
    return '300490'


def units_per_pack(label):
    """'strip of 10 tablets' → 10; '100ml bottle' → 1 (sold whole)."""
    l = (label or '').lower()
    m = re.search(r'(?:strip|blister|pack|box|bottle|jar|tube)\s+of\s+(\d+)', l) or \
        re.search(r'^(\d+)\s*(?:tablet|capsule|tab|cap|sachet|lozenge|softgel)', l)
    return int(m.group(1)) if m else 1


def paise(value):
    try:
        v = float(str(value).replace('₹', '').replace(',', '').strip())
    except ValueError:
        return 0
    return int(round(v * 100))


def pick(row, *names):
    """Column lookup tolerant of header spelling ('price(₹)', 'Price')."""
    keys = {re.sub(r'[^a-z0-9]', '', k.lower()): k for k in row}
    for n in names:
        k = keys.get(re.sub(r'[^a-z0-9]', '', n.lower()))
        if k is not None:
            return row[k]
    return ''


def entry(eid, name, salts_with_strength, manufacturer, form, pack, mrp_paise, mrp_as_of, source, ref):
    salts = [s for s, _ in salts_with_strength]
    schedule = classify(salts, ref)
    canon = [ref.canon(s) for s in salts]
    gst = 0 if canon and all(c in ref.nil for c in canon) else 5
    return {
        'id': eid,
        'n': name.strip(),
        'c': [[ref.canon(s), st] for s, st in salts_with_strength],
        'ct': ' + '.join(f'{s} {st}'.strip() for s, st in salts_with_strength),
        'm': (manufacturer or '').strip(),
        'f': (form or '').strip().lower(),
        'p': (pack or '').strip(),
        'u': units_per_pack(pack),
        'mrp': mrp_paise,
        'mrpAsOf': mrp_as_of,
        's': schedule,
        'g': gst,
        'hsn': hsn_for(salts, ref),
        'src': source,
    }


def build(brands_path, ja_path, ref, mrp_as_of='2022-11', ja_as_of=''):
    out, seen = [], set()
    brand_rows = load_csv(brands_path) if brands_path else []
    ja_rows = load_csv(ja_path) if ja_path else []
    for row in brand_rows:
        for salt, _ in split_composition(pick(row, 'short_composition1'), pick(row, 'short_composition2')):
            ref.seen[ref.canon(salt)] += 1
    for row in ja_rows:
        for salt, _ in split_composition(pick(row, 'Generic Name')):
            ref.seen[ref.canon(salt)] += 1
    if brands_path:
        for i, row in enumerate(brand_rows):
            if pick(row, 'Is_discontinued').strip().lower() in ('true', '1', 'yes'):
                continue
            name = pick(row, 'name')
            if not name.strip():
                continue
            salts = split_composition(pick(row, 'short_composition1'), pick(row, 'short_composition2'))
            key = (norm(name), norm(pick(row, 'manufacturer_name')), norm(pick(row, 'pack_size_label')))
            if key in seen:
                continue
            seen.add(key)
            out.append(entry(f"az_{pick(row, 'id') or i}", name, salts, pick(row, 'manufacturer_name'),
                             pick(row, 'type'), pick(row, 'pack_size_label'),
                             paise(pick(row, 'price(₹)', 'price')), mrp_as_of, 'az', ref))
    if ja_path:
        for row in ja_rows:
            generic = pick(row, 'Generic Name')
            if not generic.strip():
                continue
            salts = split_composition(generic)
            out.append(entry(f"ja_{pick(row, 'Drug Code')}", generic, salts, 'Jan Aushadhi (PMBI)',
                             pick(row, 'Group Name'), pick(row, 'Unit Size'),
                             paise(pick(row, 'MRP')), ja_as_of, 'janaushadhi', ref))
    return out


TSV_COLUMNS = ['id', 'name', 'composition', 'maker', 'pack', 'units', 'mrp', 'mrpAsOf', 'schedule', 'gst', 'hsn']


def _cell(v):
    return re.sub(r'[\t\r\n]+', ' ', str(v)).strip()


def write(entries, out_dir):
    """india.tsv.gz: one medicine per line (TSV_COLUMNS, no header) — compact
    and quick to scan on a phone. aliases.tsv: other names → canonical salt,
    so a search for 'amoxycillin' finds 'amoxicillin'."""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, 'india.tsv.gz')
    with gzip.open(path, 'wt', encoding='utf-8', compresslevel=9) as f:
        for e in entries:
            composition = ' + '.join(f'{c[0]} {c[1]}'.strip() for c in e['c'])
            row = [e['id'], e['n'], composition, e['m'], e['p'], e['u'], e['mrp'], e['mrpAsOf'], e['s'], e['g'], e['hsn']]
            f.write('\t'.join(_cell(v) for v in row) + '\n')
    with open(os.path.join(out_dir, 'aliases.tsv'), 'w', encoding='utf-8') as f:
        for r in load_csv(os.path.join(REF, 'salt_aliases.csv')):
            for a in r['aliases'].split('|'):
                if a.strip():
                    f.write(f"{norm(a)}\t{norm(r['canonical'])}\n")
    return path


def read_tsv(path):
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        return [dict(zip(TSV_COLUMNS, line.rstrip('\n').split('\t'))) for line in f]


def report(entries):
    sched = Counter(e['s'] for e in entries)
    gst = Counter(e['g'] for e in entries)
    unresolved = Counter(c[0] for e in entries if e['s'] == 'UNKNOWN' for c in e['c'])
    lines = [f'entries: {len(entries)}',
             'schedule: ' + ', '.join(f'{k}={v}' for k, v in sorted(sched.items())),
             'gst: ' + ', '.join(f'{k}%={v}' for k, v in sorted(gst.items())),
             'top unresolved salts (add to schedule_h.csv or salt_aliases.csv):']
    lines += [f'  {n}  {s}' for s, n in unresolved.most_common(40)]
    return '\n'.join(lines)


def selftest():
    import tempfile
    tmp = tempfile.mkdtemp()
    brands = os.path.join(tmp, 'az.csv')
    with open(brands, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['id', 'name', 'price(₹)', 'Is_discontinued', 'manufacturer_name', 'type',
                    'pack_size_label', 'short_composition1', 'short_composition2'])
        w.writerow([1, 'Augmentin 625 Duo Tablet', '223.42', 'FALSE', 'Glaxo SmithKline Pharmaceuticals Ltd',
                    'allopathy', 'strip of 10 tablets', 'Amoxycillin  (500mg) ', ' Clavulanic Acid (125mg) '])
        w.writerow([2, 'Taxim-O 200 Tablet', '108.5', 'FALSE', 'Alkem Laboratories Ltd', 'allopathy',
                    'strip of 10 tablets', 'Cefixime (200mg)', ''])
        w.writerow([3, 'Dolo 650 Tablet', '33.6', 'FALSE', 'Micro Labs Ltd', 'allopathy',
                    'strip of 15 tablets', 'Paracetamol (650mg)', ''])
        w.writerow([4, 'Old Brand', '10', 'TRUE', 'X', 'allopathy', 'strip of 10 tablets', 'Paracetamol (500mg)', ''])
        w.writerow([5, 'Ritalin 10mg Tablet', '50', 'FALSE', 'Novartis', 'allopathy', 'strip of 10 tablets',
                    'Methylphenidate (10mg)', ''])
        w.writerow([6, 'Mystery Tablet', '20', 'FALSE', 'Y', 'allopathy', 'strip of 10 tablets', 'Zzzolamide (5mg)', ''])
        w.writerow([8, 'Calpol 500 Tablet', '17.5', 'FALSE', 'GSK', 'allopathy', 'strip of 15 tablets',
                    'Paracetamol (500mg)', ''])
        w.writerow([9, 'Pacimol 650 Tablet', '30', 'FALSE', 'Ipca', 'allopathy', 'strip of 15 tablets',
                    'Paracetamol (650mg)', ''])
        w.writerow([10, 'Typo Cef Tablet', '90', 'FALSE', 'Z', 'allopathy', 'strip of 10 tablets', 'Cefiximee (200mg)', ''])
        w.writerow([11, 'Taxim-O LB Tablet', '120', 'FALSE', 'Alkem', 'allopathy', 'strip of 10 tablets',
                    'Cefixime (200mg)', 'Lactic Acid Bacillus (60Million spores)'])
        w.writerow([7, 'Voveran 50 Tablet', '40', 'FALSE', 'Novartis', 'allopathy', 'strip of 10 tablets',
                    'Diclofenac Sodium (50mg)', ''])
    h = os.path.join(tmp, 'h.csv')
    with open(h, 'w', encoding='utf-8') as f:
        f.write('salt\namoxicillin\nclavulanic acid\ndiclofenac\n')
    ref = Reference(h)
    by = {e['n']: e for e in build(brands, None, ref)}
    ok = True

    def check(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            print('FAIL', msg)

    check('Old Brand' not in by, 'discontinued dropped')
    check(by['Augmentin 625 Duo Tablet']['s'] == 'H', 'augmentin H')
    check(by['Augmentin 625 Duo Tablet']['c'][0] == ['amoxicillin', '500mg'], 'amoxycillin alias + strength')
    check(by['Augmentin 625 Duo Tablet']['hsn'] == '300410', 'penicillin hsn')
    check(by['Augmentin 625 Duo Tablet']['mrp'] == 22342, 'mrp paise')
    check(by['Augmentin 625 Duo Tablet']['u'] == 10, 'units per pack')
    check(by['Taxim-O 200 Tablet']['s'] == 'H1', 'cefixime H1')
    check(by['Taxim-O 200 Tablet']['hsn'] == '300420', 'cephalosporin hsn')
    check(by['Dolo 650 Tablet']['s'] == 'OTC', 'paracetamol OTC (not in H list)')
    check(by['Dolo 650 Tablet']['g'] == 5, 'gst 5')
    check(by['Ritalin 10mg Tablet']['s'] == 'X', 'methylphenidate X')
    check(by['Mystery Tablet']['s'] == 'UNKNOWN', 'rare unknown salt → UNKNOWN, never OTC')
    check(by['Typo Cef Tablet']['s'] == 'UNKNOWN', 'typo of an H1 salt → UNKNOWN, never OTC')
    check(by['Taxim-O LB Tablet']['s'] == 'H1', 'an H1 salt makes a combination H1 even with an unknown salt')
    check(by['Voveran 50 Tablet']['s'] == 'H', 'diclofenac sodium → diclofenac H')
    no_h = {e['n']: e for e in build(brands, None, Reference(None))}
    check(no_h['Dolo 650 Tablet']['s'] == 'UNKNOWN', 'no H list → UNKNOWN, never OTC')
    check(no_h['Taxim-O 200 Tablet']['s'] == 'H1', 'H1 known without H list')
    check(split_composition('Ibuprofen (400mg) + Paracetamol (325mg)') ==
          [('Ibuprofen', '400mg'), ('Paracetamol', '325mg')], 'split')
    path = write(list(by.values()), tmp)
    rows = read_tsv(path)
    check(len(rows) == len(by), 'round trip')
    aug = next(r for r in rows if r['name'] == 'Augmentin 625 Duo Tablet')
    check(aug['composition'] == 'amoxicillin 500mg + clavulanic acid 125mg', 'tsv composition')
    check(aug['mrp'] == '22342' and aug['schedule'] == 'H' and aug['units'] == '10', 'tsv fields')
    print(report(list(by.values())))
    print('selftest', 'OK' if ok else 'FAILED')
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--brands')
    ap.add_argument('--janaushadhi')
    ap.add_argument('--janaushadhi-date', default='', help='date the Jan Aushadhi list was downloaded, e.g. 2026-10')
    ap.add_argument('--brands-date', default='2022-11', help='month the brand prices were observed')
    ap.add_argument('--schedule-h')
    ap.add_argument('--out', default=os.path.join(ROOT, 'assets', 'catalogue'))
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not (a.brands or a.janaushadhi):
        ap.error('give --brands and/or --janaushadhi')
    ref = Reference(a.schedule_h)
    entries = build(a.brands, a.janaushadhi, ref, a.brands_date, a.janaushadhi_date)
    path = write(entries, a.out)
    rep = report(entries)
    with open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '..', 'catalogue', 'last_build_report.txt'), 'w', encoding='utf-8') as f:
        f.write(rep + '\n')
    print(rep)
    print(f'wrote {path} ({os.path.getsize(path) // 1024} KB)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
