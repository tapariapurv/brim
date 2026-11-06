#!/usr/bin/env python3
"""Single source of timing for picture and sound. Writes assets/cues.js. 100 BPM, 0.6s beat."""
import json, random, pathlib
B = .6
random.seed(7)

def typing(text, a, b):
    w = [random.uniform(.7, 1.4) * (1.5 if c == " " else 1) for c in text]
    s = sum(w); t = a; out = []
    for x in w:
        t += x / s * (b - a); out.append(round(t, 3))
    return out

PROMPT = "refactor the auth flow and add tests"
CUES = dict(
    B=B, DUR=44.4,
    level=[[0,0],[7.2,0],[8.4,.07],[12,.1],[14.4,.4],[21.6,.46],[23.2,1.14],[26.4,1.14],[27.3,.2],[28.8,.2],[29.4,.36],[31.2,.36],
           [31.5,.26],[32,.26],[32.3,.72],[32.8,.72],[33.1,1.14],[33.6,1.14],[34.1,.16],[38.4,.16],[40.2,.93],[44.4,.93]],
    heat=[[0,0],[16.8,0],[18,.75],[22.5,.75],[23.2,0],[44.4,0]],
    aurora=[[0,0],[29.2,0],[29.45,1],[30.2,1],[30.45,0],[44.4,0]],
    sunset=[[0,0],[30.2,0],[30.45,1],[31.1,1],[31.4,0],[44.4,0]],
    prompt=PROMPT, keys=typing(PROMPT, .6, 2.1),
    lines=[2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.2], hit=4.8,
    impact=7.2, impact2=42.0, click1=13.2, click2=19.8,
    rows=[round(13.5 + i * .15, 2) for i in range(8)],
    bubbles=[round(22.5 + i * .15, 2) for i in range(12)],
    swaps=[28.8, 29.4, 30.3], privacy=[31.2, 32.0, 32.8], cc=[34.2, 34.5], rc=34.8, ok=[36.6, 37.2],
)
root = pathlib.Path(__file__).resolve().parent.parent
(root / "assets/cues.js").write_text("window.C=" + json.dumps(CUES) + ";\n")
