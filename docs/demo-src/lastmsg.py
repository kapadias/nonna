"""Print the last assistant text of the newest Claude Code transcript under a projects dir."""

import glob
import json
import os
import sys

fs = sorted(
    glob.glob(os.path.join(sys.argv[1], "**", "*.jsonl"), recursive=True),
    key=os.path.getmtime,
)
last = ""
for f in fs[-1:]:
    for line in open(f):
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("type") == "assistant":
            for c in d["message"].get("content", []):
                if c.get("type") == "text" and c["text"].strip():
                    last = c["text"]
print(last)
