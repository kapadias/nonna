# expand.awk — brace lists and globs as the shell expands them, for the branch guard.
#
#   awk -f expand.awk   reads the guard's readings of a command (lib/shell-words.awk), one simple
#                       command per line, and prints each line the shell would expand, expanded;
#                       a line with nothing to expand prints nothing
#
# A brace list expands as bash 5 expands it: a{b,c}d, {x..y..n} over integers or letters, nested,
# left to right, an empty word dropped. A word that is only a range, {1..5000}, is left as written:
# it yields only numbers or single letters. A \016 before a character marks it quoted
# (shell-words.awk -v qmark=1): it is not special, and the mark is dropped.
#
# A glob is read as what it could match of what the guard looks for, never as what the disk holds:
# a path component (between / : or =) that could be git or git-<command>, main, master or develop
# is that name, and .git before hooks or config is that path. A glob group counts: bash's @(…) +(…)
# ?(…) *(…) !(…) and zsh's (a|b). Case is ignored, as macOS's disk ignores it. A name a glob could
# match counts as matched, which can only refuse more.
#
# An expansion too large to read in time (100,000 words, 2 MiB, five million steps in all, or
# lists nested 24 deep) exits 3, and the guard refuses the command.
BEGIN {
  M = sprintf("%c", 14); G = sprintf("%c", 29)
  WMAX = 100000; BMAX = 2097152; SMAX = 5000000; DMAX = 24
  for (v = 32; v < 127; v++) ASC = ASC sprintf("%c", v)
  nd = split("git git-push git-send-pack git-http-push git-subtree git-commit git-config git-merge git-am git-rebase git-cherry-pick git-revert git-pull main master develop", DICT, " ")
}
function step() { if (++steps > SMAX) exit 3 }
function ord(c) { return index(ASC, c) + 31 }

# p[1..m] as one string, joined pairwise (one-true-awk copies a string on every append).
function join(p, m,   i, r) {
  if (m == 0) return ""
  while (m > 1) {
    r = 0
    for (i = 1; i <= m; i += 2) p[++r] = (i < m ? p[i] p[i + 1] : p[i])
    m = r
  }
  return p[1]
}
function str(a, lo, hi,   i, m, sp) {
  m = 0
  for (i = lo; i <= hi; i++) sp[++m] = a[i]
  return join(sp, m)
}

# ---- Brace lists: bash's brace_expand, over the characters a[lo..hi] of one word. A list of words
# is a string, each word after a \035 (so one empty word is a lone \035).

# The } that closes each { of a[1..n], as a stack pairs them; a quoted one pairs with nothing.
function pairs(a, n,   i, sp, st) {
  split("", pt); sp = 0
  for (i = 1; i <= n; i++) {
    if (a[i] == M) { i++; continue }
    if (a[i] == "{") st[++sp] = i
    else if (a[i] == "}" && sp) pt[st[sp--]] = i
  }
}
# Where the list opened at a[p] closes, as bash's brace_gobbler finds it: going over inner lists and
# ${…} whole, the first } at its own level once a comma, or a .. not followed by }, came at that
# level; 0 if none does by hi.
function shut(a, p, hi,   i, c, commas) {
  commas = 0
  for (i = p + 1; i <= hi; i++) {
    step()
    c = a[i]
    if (c == M) { i++; continue }
    if (c == "$" && i < hi && a[i + 1] == "{") i++
    if (a[i] == "{") {
      if (!(i in pt) || pt[i] > hi) return 0 # it never closes here, so neither does this one
      i = pt[i]; continue
    }
    if (c == "}") { if (commas) return i; continue }
    if (c == ",") commas++
    else if (c == "." && i < hi && a[i + 1] == "." && !(i + 2 <= hi && a[i + 2] == "}")) commas++
  }
  return 0
}
function hascomma(a, lo, hi,   i) {
  for (i = lo; i <= hi; i++) { step(); if (a[i] == M) i++; else if (a[i] == ",") return 1 }
  return 0
}
# The words a[lo..hi] expands to. top: the whole word, where a word that is only a range stays. A
# list, then what follows it, in a loop (mawk's stack is small): bash's preamble, list, postamble.
function bx(a, lo, hi, top,   p, m, c, tack, res, pos) {
  if (++depth > DMAX) exit 3 # lists nested deeper than the guard reads
  res = G; pos = lo
  while (pos <= hi) {
    for (p = pos; p <= hi; p++) {
      step()
      c = a[p]
      if (c == M) { p++; continue }
      if (c == "$" && p < hi && a[p + 1] == "{") { # ${…} holds no list; one never closed ends the search
        if (!((p + 1) in pt) || pt[p + 1] > hi) { p = hi + 1; break }
        p = pt[p + 1]; continue
      }
      if (c == "{" && (m = shut(a, p, hi))) break
    }
    if (p > hi) { res = cross(res, G str(a, pos, hi)); break }
    if (hascomma(a, p + 1, m - 1)) tack = amble(a, p + 1, m - 1)
    else if (!seqparse(a, p + 1, m - 1)) {
      if (m == hi) { res = cross(res, G str(a, pos, hi)); break }
      tack = G str(a, p, m) # not a list: kept as written, and what follows it still expands
    }
    else if (top && p == lo && m == hi) { res = G str(a, lo, hi); break }
    else tack = seq()
    res = cross(cross(res, G str(a, pos, p - 1)), tack)
    pos = m + 1
  }
  depth--
  return res
}
# a[lo..hi] split at the commas outside inner lists, each piece expanded, the lists in turn.
function amble(a, lo, hi,   i, c, lvl, start, pc, n) {
  lvl = 0; start = lo; n = 0
  for (i = lo; i <= hi + 1; i++) {
    if (i <= hi) {
      step()
      c = a[i]
      if (c == M) { i++; continue }
      if (c == "$" && i < hi && a[i + 1] == "{") { lvl++; i++; continue }
      if (c == "{") { lvl++; continue }
      if (c == "}") { if (lvl) lvl--; continue }
      if (c != "," || lvl) continue
    }
    pc[++n] = bx(a, start, i - 1, 0)
    start = i + 1
  }
  return join(pc, n)
}
# Every word of A followed by every word of B, in bash's order.
function cross(A, B,   na, nb, x, y, i, j, r, m) {
  na = split(A, x, G) - 1; nb = split(B, y, G) - 1 # x[1] is the empty text before the first \035
  if (na * nb > WMAX || nb * length(A) + na * length(B) > BMAX) exit 3
  m = 0
  for (i = 2; i <= na + 1; i++) for (j = 2; j <= nb + 1; j++) r[++m] = G x[i] y[j]
  return join(r, m)
}
# a[lo..hi] as a range x..y[..n] of integers or of letters, read as bash reads one: 1 and the globals
# sa, sb (its ends), si (its step), sw (a zero-padded width) and sc (1 for letters), or 0.
function seqparse(a, lo, hi,   t, k, l, r, rest) {
  t = str(a, lo, hi)
  if (index(t, M) || !(k = index(t, ".."))) return 0
  l = substr(t, 1, k - 1); r = substr(t, k + 2)
  if (l ~ /^[+-]?[0-9]+$/) sc = 0
  else if (l ~ /^[A-Za-z]$/) sc = 1
  else return 0
  if (!sc && match(r, /^[+-]?[0-9]+/)) { rv = substr(r, 1, RLENGTH); rest = substr(r, RLENGTH + 1) }
  else if (sc && r ~ /^[A-Za-z]/) { rv = substr(r, 1, 1); rest = substr(r, 2) }
  else return 0
  si = 1
  if (rest != "") { if (rest !~ /^\.\.[+-]?[0-9]+$/) return 0; si = substr(rest, 3) + 0 }
  if (si < 0) si = -si
  if (si == 0) si = 1
  sw = 0
  if (sc) { sa = ord(l); sb = ord(rv); return 1 }
  sa = l + 0; sb = rv + 0
  if ((length(l) > 1 && l ~ /^0/) || (length(l) > 2 && l ~ /^-0/)) sw = length(l) # bash's padding rules
  if ((length(rv) > 1 && rv ~ /^0/) || (length(rv) > 2 && rv ~ /^-0/)) sw = length(rv)
  if (sw && sw < length(l)) sw = length(l)
  if (sw && sw < length(rv)) sw = length(rv)
  return 1
}
function seq(   n, d, i, v, r) {
  n = int((sb > sa ? sb - sa : sa - sb) / si) + 1
  if (n > WMAX) exit 3
  d = (sb >= sa ? si : -si)
  for (i = 1; i <= n; i++) {
    v = sa + (i - 1) * d
    if (v == 0) v = 0 # not -0
    # A backslash a range yields ({Z..a}) is quoting to bash, and is removed with the quotes.
    r[i] = G (sc ? (v == 92 ? "" : sprintf("%c", v)) : (sw ? sprintf("%0" sw ".0f", v) : sprintf("%.0f", v)))
  }
  return join(r, n)
}

# ---- Globs.

function isglob(t) { return t ~ ("(^|[^$" M "])[*?[(]") } # $* and $? are parameters
# The regex a glob stands for, over lowercase names: * ? and [...] (as any one character), and groups,
# whose empty alternative is written with ? (an empty one is not portable ERE).
function globre(t,   n, ch, i, c, d, lv, alts, emp, ops, g, o, j) {
  n = split(tolower(t), ch, "")
  d = 0; lv[0] = ""
  for (i = 1; i <= n; i++) {
    c = ch[i]
    if (c == M) { lv[d] = lv[d] lit(ch[++i]); continue }
    if (index("@+?*!", c) && ch[i + 1] == "(") { ops[++d] = c; lv[d] = ""; alts[d] = ""; emp[d] = 0; i++; continue }
    if (c == "(") { ops[++d] = "@"; lv[d] = ""; alts[d] = ""; emp[d] = 0; continue }
    if (d && (c == "|" || c == ")")) {
      if (lv[d] == "") emp[d] = 1
      else alts[d] = alts[d] (alts[d] == "" ? "" : "|") lv[d]
      lv[d] = ""
      if (c == "|") continue
      o = ops[d]; g = (alts[d] == "" ? "" : "(" alts[d] ")" (emp[d] ? "?" : "")); d--
      if (o == "!") g = ".*"
      else if (g != "" && o != "@") g = "(" g ")" o
      lv[d] = lv[d] g
      continue
    }
    if (c == "*") lv[d] = lv[d] ".*"
    else if (c == "?") lv[d] = lv[d] "."
    else if (c == "[" && (j = bracket(ch, i, n))) { lv[d] = lv[d] "."; i = j }
    else lv[d] = lv[d] lit(c)
  }
  return (d ? "^.*$" : "^" lv[0] "$") # a group that never closes could be anything
}
function lit(c) { return (c ~ /^[a-z0-9_-]$/ ? c : (c == "." ? "\\." : ".")) }
# The ] that closes the bracket expression opened at ch[i], or 0.
function bracket(ch, i, n,   j) {
  j = i + 1
  if (ch[j] == "!" || ch[j] == "^") j++
  if (ch[j] == "]") j++
  for (; j <= n; j++) {
    if (ch[j] == M) { j++; continue }
    if (ch[j] == "[" && ch[j + 1] == ":") {
      for (j += 2; j < n && !(ch[j] == ":" && ch[j + 1] == "]"); j++);
      j++; continue
    }
    if (ch[j] == "]") return j
  }
  return 0
}
# Could the path component t be name? A literal one is it, case aside. A glob stands for a dot file
# only when it starts with a dot, a bracket or a group, as bash's globs do.
function could(t, name,   u) {
  u = t; gsub(M, "", u)
  if (!isglob(t)) return tolower(u) == name
  if (name ~ /^\./ && u !~ /^(\.|\[|[@+?*!]?\()/) return 0
  return name ~ globre(t)
}
# w with each component that is a glob read as the name of hers it could be.
function globs(w,   n, ch, i, c, d, cur, m, cp, sp, nc, j, k, changed) {
  n = split(w, ch, "")
  nc = 0; m = 0; d = 0
  for (i = 1; i <= n + 1; i++) {
    c = (i <= n ? ch[i] : "")
    if (c == M) { cur[++m] = c ch[i + 1]; i++; continue }
    if (i > n || c == "/" || ((c == ":" || c == "=") && !d)) { cp[++nc] = join(cur, m); sp[nc] = c; m = 0; continue }
    if (c == "(") d++
    else if (c == ")" && d) d--
    cur[++m] = c
  }
  changed = 0
  for (j = 1; j <= nc; j++) {
    if (j < nc && sp[j] == "/" && (isglob(cp[j]) || isglob(cp[j + 1])) && could(cp[j], ".git") \
      && (could(cp[j + 1], "hooks") || could(cp[j + 1], "config"))) {
      cp[j] = ".git"; cp[j + 1] = (could(cp[j + 1], "hooks") ? "hooks" : "config"); changed = 1; j++
      continue
    }
    if (!isglob(cp[j])) continue
    for (k = 1; k <= nd; k++) if (could(cp[j], DICT[k])) { cp[j] = DICT[k]; changed = 1; break }
  }
  if (!changed) return w
  for (j = 1; j <= nc; j++) cp[j] = cp[j] sp[j]
  return join(cp, nc)
}

{
  if ($0 in seen) next
  seen[$0] = 1
  if ($0 !~ /[{*?[(]/) next
  line = $0; gsub(G, "?", line)
  n = split(line, w, /[ \t]+/)
  m = 0; changed = 0
  for (j = 1; j <= n; j++) {
    if (w[j] == "") continue
    r = w[j]
    if (index(r, "{")) {
      na = split(r, A, ""); pairs(A, na)
      k = split(bx(A, 1, na, 1), x, G); q = 0
      for (i = 2; i <= k; i++) if (x[i] != "") { if (++W > WMAX) exit 3; o[++q] = x[i] (i < k ? " " : "") }
      r = join(o, q)
    }
    if (r ~ /[*?[(]/) {
      k = split(r, x, " ")
      for (i = 1; i <= k; i++) o[i] = globs(x[i]) (i < k ? " " : "")
      r = join(o, k)
    }
    gsub(M, "", r)
    v = w[j]; gsub(M, "", v)
    if (r != v) changed = 1
    out[++m] = r (j < n ? " " : "")
  }
  if (!changed) next
  r = join(out, m)
  if ((B += length(r)) > BMAX) exit 3
  print r
}
