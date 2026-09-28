# Where the real suite comes from

**The repository.** [fastapi/full-stack-fastapi-template](https://github.com/fastapi/full-stack-fastapi-template),
MIT licensed, at the commit [`UPSTREAM`](UPSTREAM) pins. It is not copied into this repository:
`lib/real/cache.sh` fetches it at that commit, and checks its tree hash, before the first run.

**Three ordinary tickets** (`search`, `csv-export`, `bulk-delete`) are adapted from the backend
tasks of ponytail's agentic benchmark: `tmpl-be-search`, `tmpl-be-csv` and `tmpl-be-bulkdelete`, in
`benchmarks/agentic/tasks.py` of [ponytail](https://github.com/DietrichGebert/ponytail) v4.10.0
(commit `1d95ff7`), MIT licensed. The wording here is ours. Each prompt spells out the interface
(the URL, the response and who may see what), so that a hidden test can check it.

**Three trap tickets** (`priority`, `argon2-cost`, `keep-items`) were written for this benchmark by
Nonna's maintainer, with Claude Code, as were every hidden test under `hidden/real/` and every
reference patch under `verify/real/`.
