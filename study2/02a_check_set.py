#!/usr/bin/env python3
"""
Modeling Guilty Minds, Study 2
Stage 2a: draw the check set and make the hand-coding sheet

Run from the analysis folder:   python3 02a_check_set.py

Registered rule (preregistration, "Justification coding protocol", "Check set"):
before anyone examines an automated code, David G. Kamper hand-codes a stratified
random sample of 100 Study 1 justifications (60 Knowledge, 20 Recklessness,
10 Negligence, 10 Blamelessness). Coders see only the justification text and the
defendant's name for that case. They never see the chosen category, the slider
rating, the probe answers, or the vignette features.

The sampling frame is the 1,060 analysed Study 1 trials: the 212 sessions with all
five cases, as in the Study 1 analysis script. The frame is sorted by session and
position, and the sample is drawn with numpy's default generator and a fixed seed,
so anyone can redraw it. The 100 items are then put in a random order with the same
generator, so the sheet does not group them by category.

The defendant's name for each case is read from the Study 1 session files, from the
vignette shown on the slider page. The script checks, for every session it reads,
that the vignette at each position matches the combined trial file.

Inputs
  data/study1_trials.csv     the Study 1 combined trial file
  data/study1_raw/*.csv      the Study 1 Pavlovia session files (for the names)

Outputs
  protocol/check_set_key.csv            item -> Study 1 session, position, vignette.
                                        No category or rating, but leave it closed
                                        until the coding is done.
  protocol/check_set_items.csv          item, defendant's name, justification
  protocol/check_set_coding_sheet.xlsx  the sheet to fill in (written only when
                                        every item has its name)
  data/study1_names.csv                 the defendant's name for every Study 1 trial
                                        whose session file is present

The console output gives counts only. It prints no justification and no category
of any sampled item.
"""
import csv
import glob
import math
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 20261007
STRATA = {"Knowledge": 60, "Recklessness": 20, "Negligence": 10, "Blamelessness": 10}
NAMES = ["John", "David", "Andrew", "Robert", "Daniel"]
CODES = [
    ("Knew", "The text says or implies that he knew, or was practically certain, that the package held illicit material."),
    ("Suspected", "The text says or implies that he was aware of a possibility or risk that it did."),
    ("Unaware, at fault", "He did not know or suspect, but a careful person would have."),
    ("Unaware, no fault", "He did not know or suspect and had no reason to."),
    ("Act or situation only", "The text bases the judgment on awareness of what he was doing or where he was, such as carrying a package across a border, without addressing the contents."),
    ("Evidentiary", "The text bases the judgment on what can or cannot be proven, not on his state of mind."),
    ("Uncodable", "The text is empty, off topic, or too short to classify."),
]
RULES = [
    "Each justification gets one of seven codes for what it says about the defendant's mental state regarding the contents.",
    "When a text fits more than one code, statements about the contents take precedence over the act-or-situation and evidentiary codes.",
    "\"He didn't know\" with no further qualification is coded as unaware in every category.",
    "Code what the text says or implies. Do not try to guess which option the participant chose, and do not look the case up in the Study 1 data.",
]

out = Path("protocol")
out.mkdir(exist_ok=True)

# ---------------------------------------------------------------------------
# 1. Sampling frame: the analysed Study 1 trials
# ---------------------------------------------------------------------------
trials = pd.read_csv("data/study1_trials.csv", dtype=str, keep_default_na=False)
per_session = trials.groupby("session_id").size()
frame = trials[trials["session_id"].isin(per_session[per_session == 5].index)].copy()
frame["vignette_position"] = frame["vignette_position"].astype(int)
frame["vignette_id"] = frame["vignette_id"].str.zfill(6)
frame = frame.sort_values(["session_id", "vignette_position"]).reset_index(drop=True)
assert len(frame) == 1060 and frame["session_id"].nunique() == 212, "unexpected Study 1 frame"
assert set(frame["judgment"]) == set(STRATA), "unexpected category labels"

# ---------------------------------------------------------------------------
# 2. Draw the stratified sample, then shuffle the 100 items
# ---------------------------------------------------------------------------
rng = np.random.default_rng(SEED)
picked = []
for category, n in STRATA.items():
    pool = frame.index[frame["judgment"] == category].to_numpy()
    picked.extend(rng.choice(pool, size=n, replace=False).tolist())
order = rng.permutation(len(picked))
sample = frame.loc[[picked[i] for i in order]].reset_index(drop=True)
sample.insert(0, "item", [f"C{i:03d}" for i in range(1, len(sample) + 1)])
assert sample.groupby("judgment").size().to_dict() == STRATA

# ---------------------------------------------------------------------------
# 3. Defendant's names from the Study 1 session files
# ---------------------------------------------------------------------------
def names_by_position(path):
    found = {}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            if row.get("trial_type") != "html-slider-response":
                continue
            m = re.search(r'<div class="vignette-title">Scenario (\d+)</div>\s*(\w+) is an American citizen',
                          row.get("stimulus") or "")
            if m:
                found[int(m.group(1))] = (m.group(2), (row.get("vignette_id") or "").zfill(6))
    return found

raw_files = {}
for p in glob.glob("data/study1_raw/*.csv"):
    m = re.search(r"SESSION_(.+)\.csv$", p)
    if m:
        raw_files[m.group(1)] = p

name_rows = []
for sid, group in frame.groupby("session_id"):
    if sid not in raw_files:
        continue
    found = names_by_position(raw_files[sid])
    assert sorted(found) == [1, 2, 3, 4, 5], f"session {sid}: names not found for all five positions"
    for _, t in group.iterrows():
        name, vid = found[t["vignette_position"]]
        assert vid == t["vignette_id"], f"session {sid}: vignette at position {t['vignette_position']} does not match"
        assert name in NAMES, f"session {sid}: unexpected name"
        name_rows.append({"session_id": sid, "vignette_position": t["vignette_position"], "defendant": name})
names = pd.DataFrame(name_rows, columns=["session_id", "vignette_position", "defendant"])
names.to_csv("data/study1_names.csv", index=False)

sample = sample.merge(names, on=["session_id", "vignette_position"], how="left")
sample["defendant"] = sample["defendant"].fillna("")

# ---------------------------------------------------------------------------
# 4. Write the key and the items
# ---------------------------------------------------------------------------
sample[["item", "session_id", "vignette_position", "vignette_id"]].to_csv(out / "check_set_key.csv", index=False)
sample[["item", "defendant", "justification"]].to_csv(out / "check_set_items.csv", index=False)

missing = sample[sample["defendant"] == ""]
mentions = missing["justification"].apply(lambda t: sorted({n for n in NAMES if re.search(rf"\b{n}\b", t)}))
print(f"Study 1 sessions with a session file: {names['session_id'].nunique()} of 212")
print(f"Check set: {len(sample)} items, " + ", ".join(f"{k} {v}" for k, v in STRATA.items()))
print(f"Items with the defendant's name: {len(sample) - len(missing)}; without: {len(missing)}")
if len(missing):
    print(f"  of those without, the text names one of the five names in {sum(len(m) == 1 for m in mentions)}, "
          f"none in {sum(len(m) == 0 for m in mentions)}, more than one in {sum(len(m) > 1 for m in mentions)}")
    print(f"  sessions still needed for the check set: {missing['session_id'].nunique()}")

if len(missing) and "--allow-missing-names" not in sys.argv:
    print("\nThe coding sheet is written once every item has its name. Put the missing Study 1 "
          "session files in data/study1_raw/ and run this again.")
    sys.exit(0)

# ---------------------------------------------------------------------------
# 5. The coding sheet
# ---------------------------------------------------------------------------
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation

FONT = "Arial"
regular = Font(name=FONT, size=10)
bold = Font(name=FONT, size=10, bold=True)
title_font = Font(name=FONT, size=13, bold=True)
grey = Font(name=FONT, size=10, color="595959")
yellow = PatternFill("solid", fgColor="FFF2CC")
header_fill = PatternFill("solid", fgColor="D9D9D9")
example_fill = PatternFill("solid", fgColor="F2F2F2")
thin = Side(style="thin", color="BFBFBF")
box = Border(left=thin, right=thin, top=thin, bottom=thin)
wrap_top = Alignment(wrap_text=True, vertical="top")

wb = Workbook()
ws = wb.active
ws.title = "Coding"
cb = wb.create_sheet("Codebook")

# Codebook tab
cb.column_dimensions["A"].width = 24
cb.column_dimensions["B"].width = 100
cb["A1"] = "Codebook for the justification codes"
cb["A1"].font = title_font
cb["A3"] = "Code"
cb["B3"] = "Use it when"
for c in ("A3", "B3"):
    cb[c].font = bold
    cb[c].fill = header_fill
    cb[c].border = box
first_code_row = 4
for i, (code, meaning) in enumerate(CODES):
    r = first_code_row + i
    cb.cell(r, 1, code).font = bold
    cb.cell(r, 2, meaning).font = regular
    for col in (1, 2):
        cb.cell(r, col).alignment = wrap_top
        cb.cell(r, col).border = box
    cb.row_dimensions[r].height = 15 * max(1, math.ceil(len(meaning) / 105)) + 3
last_code_row = first_code_row + len(CODES) - 1
r = last_code_row + 2
cb.cell(r, 1, "Rules").font = bold
for i, rule in enumerate(RULES, start=1):
    cb.cell(r + i, 1, f"{i}.").font = regular
    cb.cell(r + i, 1).alignment = Alignment(vertical="top")
    cb.cell(r + i, 2, rule).font = regular
    cb.cell(r + i, 2).alignment = wrap_top
    cb.row_dimensions[r + i].height = 15 * max(1, math.ceil(len(rule) / 105)) + 3
r = r + len(RULES) + 2
cb.cell(r, 1, "Source").font = bold
cb.cell(r, 1).alignment = Alignment(vertical="top")
cb.cell(r, 2, "The codes, their meanings and the first three rules are the registered codebook "
              "(Study 2 preregistration, Justification coding protocol). The automated coder "
              "receives the same codebook.").font = grey
cb.cell(r, 2).alignment = wrap_top
cb.row_dimensions[r].height = 33

# Coding tab
widths = {"A": 8, "B": 12, "C": 90, "D": 24, "E": 30}
for col, w in widths.items():
    ws.column_dimensions[col].width = w
ws["A1"] = "Study 2 check set: hand codes for 100 Study 1 justifications"
ws["A1"].font = title_font
legend = [
    "Fill in the yellow Code column only, choosing one code per row from the list. The Note column is optional.",
    "Read the Codebook tab first. Each row shows only the justification and the defendant's name for that case.",
    "Please do not look the cases up in the Study 1 data while coding, and code all 100 before anyone looks at an automated code.",
]
for i, line in enumerate(legend, start=2):
    ws.cell(i, 1, line).font = regular
ws["A6"] = "Coded so far"
ws["A6"].font = bold
header_row = 9
first_item_row = header_row + 1
last_item_row = header_row + len(sample)
ws["C6"] = f'=COUNTA(D{first_item_row}:D{last_item_row})&" of {len(sample)}"'
ws["C6"].font = bold

ws["A8"] = "Example"
ws["B8"] = "Robert"
ws["C8"] = "(Made up, not part of the check set.) He took $1000 from a stranger to carry a duffel bag across the border, so he knew it was drugs."
ws["D8"] = "Knew"
ws["E8"] = "Format only"
for col in range(1, 6):
    cell = ws.cell(8, col)
    cell.font = grey
    cell.fill = example_fill
    cell.alignment = wrap_top
    cell.border = box
ws.row_dimensions[8].height = 30

headers = ["Item", "Defendant", "Justification", "Code", "Note (optional)"]
for col, h in enumerate(headers, start=1):
    cell = ws.cell(header_row, col, h)
    cell.font = bold
    cell.fill = header_fill
    cell.border = box
    cell.alignment = Alignment(vertical="center")

for i, row in sample.iterrows():
    r = first_item_row + i
    text = row["justification"]
    values = [row["item"], row["defendant"], text, None, None]
    for col, v in enumerate(values, start=1):
        cell = ws.cell(r, col, v)
        cell.font = regular
        cell.alignment = wrap_top
        cell.border = box
    ws.cell(r, 4).fill = yellow
    ws.row_dimensions[r].height = 13.5 * max(1, math.ceil(len(text) / 95)) + 4

dv = DataValidation(type="list", formula1=f"=Codebook!$A${first_code_row}:$A${last_code_row}",
                    allow_blank=True, showErrorMessage=True,
                    errorTitle="Not a code", error="Choose one of the seven codes from the list.")
ws.add_data_validation(dv)
dv.add(f"D{first_item_row}:D{last_item_row}")
ws.freeze_panes = ws.cell(first_item_row, 1)
ws.sheet_view.zoomScale = 110

# Printing: landscape, all columns on one page width, header row repeated.
for sheet in (ws, cb):
    sheet.page_setup.orientation = "landscape"
    sheet.page_setup.fitToWidth = 1
    sheet.page_setup.fitToHeight = 0
    sheet.sheet_properties.pageSetUpPr.fitToPage = True
ws.print_title_rows = f"{header_row}:{header_row}"

path = out / "check_set_coding_sheet.xlsx"
wb.save(path)
print(f"\nWrote {path}")
