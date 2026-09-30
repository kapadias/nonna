# shellcheck shell=bash
# Sourced helper — the apply_patch format, read by its grammar, a file at a time (ADR-0013). A host
# that edits with such a patch (Codex does) sends several files in one call, where Nonna's gates judge
# one file a call: the host's adapter turns each record this prints into the payload its gates read.
# Nothing here knows which host sent the patch.

# nonna_patch_files
#   Reads a patch (*** Begin Patch ... *** End Patch) on stdin and prints one record a line for each
#   file it touches, in its order:
#     <op> TAB <path> TAB <moved to> TAB <added lines>
#   <op> is Add, Update or Delete; <moved to> is empty unless an Update moves the file; <added lines>
#   are the lines the patch adds to the file, joined by \n. Each field but <op> is written as the
#   inside of a JSON string, so a record is one line, a field holds no tab, and a JSON payload can take
#   a field as it is. To refuse a patch it prints nothing and returns non-zero: 1 for a patch it
#   cannot read with certainty; 3 for one over 256 KB, and 4 for one that touches over 200 files (a
#   move touches two), too much to check a file at a time before a hook times out, since a hook that
#   times out does not block.
#   The grammar is read as an allowlist, and a line it does not allow refuses the patch: following
#   each of a parser's trim rules instead is how a header would slip past. In an Add hunk, a line that
#   starts with + is a line it adds. In an Update hunk, a line that is empty or starts with a space,
#   +, - or @@, or is *** End of File, belongs to the hunk and is never a header, and *** Move to:
#   counts only on the line after the hunk's header, as it is written. Every other line must be
#   *** Begin Patch, *** End Patch or a file header once spaces, tabs and CRs are stripped from its
#   ends. A path, a header's or a move's, whose first or last character is a blank, a control
#   character or non-ASCII is refused: a parser trims some of these, and the gate cannot know the
#   path it would write. A CR at a line's end is dropped first, as a parser splits lines, and a patch
#   that names no file is refused: the grammar puts one in every patch.
#   A \001 in the patch (how a caller keeps a NUL byte, lib/secret-patterns.sh) is written as \u0001.
#   Characters are escaped one at a time and joined pairwise, in n log n time in any awk (as
#   lib/json.sh decodes).
nonna_patch_files() {
  LC_ALL=C awk -v most_bytes=262144 -v most_files=200 '
    function joined(   m, j) {
      while (np > 1) {
        m = 0
        for (j = 1; j <= np; j += 2) p[++m] = (j < np ? p[j] p[j + 1] : p[j])
        np = m
      }
      return (np ? p[1] : "")
    }
    function esc(s,   n, i, c) {
      n = split(s, ch, ""); np = 0
      for (i = 1; i <= n; i++) { c = ch[i]; p[++np] = (c in E) ? E[c] : c }
      return joined()
    }
    function file(op, path) {
      nf++; kd[nf] = op; pa[nf] = esc(path); mv[nf] = ""; lo[nf] = nl + 1; hi[nf] = nl
      return nf
    }
    function added(line) { ln[++nl] = esc(substr(line, 2)); hi[cur] = nl }
    function edge_ok(path) { # printable ASCII at both ends: nothing a parser could trim
      return path != "" && index(PRINTABLE, substr(path, 1, 1)) && index(PRINTABLE, substr(path, length(path), 1))
    }
    BEGIN {
      for (i = 1; i < 32; i++) E[sprintf("%c", i)] = sprintf("\\u%04x", i)
      E["\\"] = "\\\\"; E["\""] = "\\\""
      for (i = 33; i < 127; i++) PRINTABLE = PRINTABLE sprintf("%c", i)
    }
    {
      size += length($0) + 1
      if (size > most_bytes) { big = 1; exit }
      line = $0; sub(/\r$/, "", line)
      if (st == "add") {
        if (substr(line, 1, 1) == "+") { added(line); next }
        st = ""
      }
      if (st == "update") {
        if (first && index(line, "*** Move to: ") == 1) {
          first = 0; to = substr(line, 14)
          if (!edge_ok(to)) { bad = 1; exit }
          mv[cur] = esc(to); next
        }
        first = 0; c = substr(line, 1, 1)
        if (c == "+") { added(line); next }
        if (line == "" || c == " " || c == "-" || index(line, "@@") == 1 || line == "*** End of File") next
        st = ""
      }
      t = line; sub(/^[ \t\r]+/, "", t); sub(/[ \t\r]+$/, "", t)
      if (t == "*** Begin Patch" || t == "*** End Patch") next
      if (index(t, "*** Add File: ") == 1) { op = "Add"; path = substr(t, 15); st = "add" }
      else if (index(t, "*** Update File: ") == 1) { op = "Update"; path = substr(t, 18); st = "update"; first = 1 }
      else if (index(t, "*** Delete File: ") == 1) { op = "Delete"; path = substr(t, 18); st = "" }
      else { bad = 1; exit }
      if (!edge_ok(path)) { bad = 1; exit }
      cur = file(op, path)
      if (st == "") cur = 0
    }
    END {
      if (big) exit 3
      if (bad || !nf) exit 1
      files = nf
      for (i = 1; i <= nf; i++) if (mv[i] != "") files++
      if (files > most_files) exit 4
      for (i = 1; i <= nf; i++) {
        np = 0
        for (k = lo[i]; k <= hi[i]; k++) { if (np) p[++np] = "\\n"; p[++np] = ln[k] }
        printf "%s\t%s\t%s\t%s\n", kd[i], pa[i], mv[i], joined()
      }
    }'
}
