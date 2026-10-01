# shell-words.awk — a shell command as the shell will see it, for the branch guard.
#
#   awk -v out=A -f shell-words.awk   one simple command per line, each word kept whole (whitespace
#                                     inside a quoted word becomes \001), quotes and escapes removed
#   awk -v out=B -f shell-words.awk   quotes and escapes removed, whitespace kept, and every
#                                     ; & | ( ) ` a line break, quoted or not, so code inside a
#                                     quoted string (sh -c "…", "$(…)") is seen too
#   add -v nomask=1                   to mask nothing (the guard reads B's own output again, so a
#                                     quote nested in a quoted string is removed too); with
#                                     -v relevel=1, the \002 marks that output carries are dropped
#   add -v qmark=1                    to mark each quoted character that brace expansion or a glob
#                                     would treat as special ({ } , . $ * ? [ ( ) | @ + !) with a
#                                     \016 before it, for lib/expand.awk (a \016 in the command is ?)
#   add -v xglob=1                    to keep a glob group inside its word: a ( that follows a
#                                     character of the word (bash's @(…) with extglob on, zsh's
#                                     (a|b)) runs to its ), whitespace in it a \001; in B, ( ) and |
#                                     inside a word stay. Only the expander reads this: a ( there is
#                                     otherwise a syntax error, or a subshell the other readings see
#
# A redirection the shell performs prints with a \002 mark before it (\0022> x), which no word can
# carry (a \002 in a word prints as ?): a quoted '>' or an escaped 2\>x is a value, not a
# redirection, and the guard sets aside only what is marked.
#
# The guard checks every reading: a match in any refuses.
#
# A message is masked as MSG, so its words are not read as flags or refs: the value of -m, --message,
# -F or --file (-am and the like for commit and tag) in git commit, merge, tag, stash and notes, and
# of --title, --body, --notes, --subject or --comment in gh pr, issue and release. Only where this
# reading is the shell's own: before the first $( ` ${ $[ <( >( or << (whose nested quoting it does
# not follow; a plain ${NAME} has none), in a word the shell finishes, before any redirection or --
# in that command, and only when no earlier word could take the flag as its own value (-t -m "…"
# gives -m to -t). Anything else stays exposed, which can only refuse more, never less.
#
# Claude Code's usual message, "$(cat <<'EOF' … EOF\n)", is literal (a quoted delimiter expands
# nothing): it is one quoted word, its body, when it opens outside any quote, ends exactly where the
# shell ends it, and its body holds no " $ ` or backslash (see heredoc_at). $'…' escapes are
# decoded as bash decodes them. Comments are skipped as the shell skips them; $IFS is a space.
#
# It reads in n log n time in any awk: one-true-awk (macOS's) measures and copies a string on every
# substr() and append, so the input is one record, split once into characters; a word is built from
# pieces joined pairwise; and look-aheads join a bounded stretch. A hook that outran Claude Code's
# timeout would not block. The guard runs it with LC_ALL=C: shell syntax is ASCII, and the bytes of
# a UTF-8 character never look like it.
BEGIN { for (v = 32; v < 127; v++) ASCII = ASCII sprintf("%c", v); RS = sprintf("%c", 1) }
{ s = s (NR > 1 ? RS : "") $0 }

# ch[i .. i+len-1] as one string, its pieces joined pairwise.
function S(i, len,   j, m, r) {
  m = 0
  for (j = i; j < i + len && j <= n; j++) sp[++m] = ch[j]
  while (m > 1) {
    r = 0
    for (j = 1; j <= m; j += 2) sp[++r] = (j < m ? sp[j] sp[j + 1] : sp[j])
    m = r
  }
  return (m ? sp[1] : "")
}
function wadd(t) { if (t != "") wp[++np] = t } # a piece of the word being read
function qm(t) { if (qmark) gsub(/[[{},.$*?()|@+!]/, "\016&", t); return t } # a quoted piece
function wstr(   m, i) { # the word so far: its pieces joined pairwise, then kept as one piece
  while (np > 1) {
    m = 0
    for (i = 1; i <= np; i += 2) wp[++m] = (i < np ? wp[i] wp[i + 1] : wp[i])
    np = m
  }
  return (np ? wp[1] : "")
}
function endword(   w) {
  if (np == 0 && !q) return
  w = wstr()
  k++; tok[k] = w; tq[k] = q; tpre[k] = (q ? pre : w); tsep[k] = ""; tsync[k] = sync
  np = 0; q = 0; pre = ""; esc = 0
}
function sep(c) { k++; tok[k] = c; tsep[k] = c; tq[k] = 0; tsync[k] = sync }
# A redirection: digits written right before it, unquoted and unescaped, are its file descriptor
# (2>x) and print with it; with a space between (2 >x), or quoted, they are an argument.
function redir(op) {
  if (np && !q && !esc && wstr() ~ /^[0-9]+$/) { k++; tok[k] = wstr() op; tsep[k] = op; tq[k] = 0; tsync[k] = sync; np = 0; pre = ""; return }
  endword(); sep(op)
}

# At a double quote, ch[i]: when "$(cat <<'D'<nl>…<nl>D<nl>)" follows, the body is left in hd and the
# index of the closing quote is returned, else 0. The first line that begins with D must be exactly
# D, then only blanks up to )": bash 5.2 also ends the heredoc at "D)", and <<- at a tab-indented D.
# The body may hold no " $ ` or backslash: macOS /bin/bash 3.2 ends the $( at a ) inside the body,
# and what follows is read as double-quoted text, where only those can run or end anything.
function heredoc_at(i,   t, h, d, body, p, rest, e, after) {
  if (S(i + 1, 5) != "$(cat") return 0 # before joining the rest of the command
  t = S(i + 1, n - i)
  if (!match(t, /^\$\(cat[ \t]*<<[ \t]*'[A-Za-z_][A-Za-z_0-9]*'[ \t]*\n/)) return 0
  h = RLENGTH; d = substr(t, 1, h); sub(/^[^']*'/, "", d); sub(/'.*$/, "", d)
  body = substr(t, h + 1)
  p = index("\n" body, "\n" d)
  if (p == 0) return 0
  rest = substr(body, p); e = index(rest, "\n")
  if (e == 0 || substr(rest, 1, e - 1) != d) return 0
  after = substr(rest, e + 1)
  if (!match(after, /^[ \t\n]*\)"/)) return 0
  hd = (p > 1 ? substr(body, 1, p - 2) : "")
  if (hd ~ /["$`\\]/) return 0
  return i + h + p + e + RLENGTH - 1
}

# $'…' as bash decodes it: a NUL ends the string (bash drops the rest), and a byte beyond ASCII,
# which cannot spell a flag or a ref, stays a placeholder. Returns the index of the escape's last char.
function put(t) { if (!cut) wadd(qm(t)) }
function chr(v) { if (v == 0) { cut = 1; return "" } return (v < 128 ? sprintf("%c", v) : "?") }
function ansi_c(i,   nx, j, v, m, d, h, codes) {
  nx = ch[i + 1]
  if (nx == "") { put("\\"); return i }
  j = index("abeEfnrtv", nx)
  if (j) { split("7 8 27 27 12 10 13 9 11", codes, " "); put(chr(codes[j] + 0)); return i + 1 }
  if (nx == "\\" || nx == "'" || nx == "\"" || nx == "?") { put(nx); return i + 1 }
  if (nx ~ /[0-7]/) {
    v = 0
    for (m = 1; m <= 3 && ch[i + m] ~ /^[0-7]$/; m++) v = v * 8 + ch[i + m]
    put(chr(v % 256)); return i + m - 1
  }
  if (nx == "x" || nx == "u" || nx == "U") {
    d = (nx == "x" ? 2 : (nx == "u" ? 4 : 8)); v = 0
    for (m = 2; m <= d + 1; m++) {
      h = ch[i + m]
      if (h == "" || !index("0123456789abcdefABCDEF", h)) break
      v = v * 16 + index("0123456789abcdef", tolower(h)) - 1
    }
    if (m == 2) { put("\\" nx); return i + 1 } # no digits: bash keeps it as written
    put(chr(nx == "x" ? v % 256 : v)); return i + m - 1
  }
  if (nx == "c" && ch[i + 2] != "") {
    h = ch[i + 2]
    put(chr(h == "?" ? 127 : (index(ASCII, toupper(h)) + 31) % 32)); return i + 2
  }
  put("\\" nx); return i + 1
}

# ${NAME}, ${#NAME} or ${1} at ch[i]: a plain parameter holds no quoting of its own.
function plainparam(i) { return S(i, 256) ~ /^\$\{(#?[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-])\}/ }

# The option before a separate message flag must be one that takes no value of its own.
function novalue(t, kind) {
  if (t ~ /^--[A-Za-z][A-Za-z0-9-]*=/) return 1
  if (kind == "c" ? t ~ /^-[aqsve]+$/ : t ~ /^-[aqve]+$/) return 1
  return t ~ /^--(amend|allow-empty|allow-empty-message|no-edit|edit|signoff|quiet|verbose|all|annotate|sign|force|no-ff|ff|ff-only|no-commit|commit|staged|keep-index|include-untracked|reset-author)$/
}
function msgflag(t, kind) {
  if (t == "-m" || t == "--message" || t == "-F" || t == "--file") return 1
  return (kind == "c" ? t ~ /^-[aqsve]+m$/ : t ~ /^-[aqve]+m$/)
}

END {
  if (substr(s, length(s)) == "\n") s = substr(s, 1, length(s) - 1) # as reading by lines would
  if (relevel) gsub(sprintf("%c", 2), "", s) # the marks on redirections this reading printed before
  if (qmark) gsub(/\016/, "?", s)
  gsub(/\$\{IFS\}|\$IFS/, " ", s)
  n = split(s, ch, ""); s = ""
  state = 0; np = 0; q = 0; pre = ""; esc = 0; k = 0; sync = 1; cut = 0; gd = 0
  for (i = 1; i <= n; i++) {
    c = ch[i]; nx = ch[i + 1]
    if (state == 0 && gd) { # in a glob group (xglob): the word goes on to its ), a line ends it
      if (c == "\n") gd = 0
      else if (c != "\\" && c != "'" && c != "\"" && !(c == "$" && (nx == "'" || nx == "\""))) {
        if (c == "(") gd++
        else if (c == ")") gd--
        wadd(c == " " || c == "\t" ? "\001" : c)
        continue
      }
    }
    if (state == 0) {
      # $( ` ${ $[ <( >( and << open what this reading does not follow: from here on its quoting may
      # part from the shell's, so nothing more is masked.
      if ((c == "$" && (nx == "(" || nx == "[" || (nx == "{" && !plainparam(i)))) || c == "`" || ((c == "<" || c == ">") && nx == "(") || (c == "<" && nx == "<")) sync = 0
      if (c == "\\") { i++; if (nx != "\n") { wadd(qm(nx)); esc = 1 } }
      else if ((c == ">" || c == "<") && (nx == "|" || nx == "&" || (c == "<" && nx == ">"))) { redir(c == "<" && nx == ">" ? ">" : c); i++ } # >| >& <& <>: one redirection
      else if (c == "&" && nx == ">") { endword(); sep(">"); i++ } # &> and &>>: a redirection, not a separator
      else if (c == "'") { if (!q) pre = wstr(); q = 1; state = 1 }
      else if (c == "\"") {
        if (!q) pre = wstr()
        q = 1
        if (sync && (e = heredoc_at(i))) { wadd(qm(hd)); i = e } else state = 2
      }
      else if (c == "$" && nx == "'") { if (!q) pre = wstr(); q = 1; state = 3; cut = 0; i++ }
      else if (c == "$" && nx == "\"") { if (!q) pre = wstr(); q = 1; state = 2; i++ }
      else if (c == "#" && np == 0 && !q) { while (i < n && ch[i + 1] != "\n") i++ }
      else if (c == " " || c == "\t") endword()
      else if (xglob && c == "(" && (np || q) && ch[i - 1] != "$") { gd = 1; wadd(c) }
      else if (c == "<" || c == ">") redir(c)
      else if (c ~ /[;&|()`\n]/) { endword(); sep(c) }
      else wadd(c)
    } else if (state == 1) {
      if (c == "'") state = 0; else wadd(qm(c))
    } else if (state == 3) {
      if (c == "\\") i = ansi_c(i)
      else if (c == "'") state = 0
      else put(c)
    } else {
      if (c == "\\" && (nx == "\"" || nx == "\\" || nx == "$" || nx == "`" || nx == "\n")) { i++; if (nx != "\n") wadd(qm(nx)) }
      else if (c == "\"") state = 0
      else {
        if (c == "`" || (c == "$" && (nx == "(" || nx == "[" || (nx == "{" && !plainparam(i))))) sync = 0
        wadd(qm(c))
      }
    }
  }
  if (state != 0) sync = 0 # a word the shell never finishes
  endword()

  # kind: "" nothing to mask; "o" git's options before its subcommand; "c" commit or tag; "m" merge,
  # stash or notes; "h1" gh before pr/issue/release; "h" gh pr/issue/release.
  start = 1; kind = ""; pend = 0; free = 1; skip = 0
  for (j = 1; j <= k && !nomask; j++) {
    if (!tsync[j]) break # from here this reading may not be the shell's
    if (tsep[j] != "") {
      if (tsep[j] ~ /[<>]/) kind = "" # a redirection: nothing more to mask in this command
      else { start = 1; kind = "" }
      pend = 0
      continue
    }
    t = tok[j]
    if (start) {
      if (!tq[j] && t ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/) continue # an assignment before the command
      if (!tq[j] && t ~ /^(if|then|else|elif|do|while|until|time|!|\{)$/) continue # a reserved word
      start = 0; pend = 0; free = 1; skip = 0
      kind = (tq[j] ? "" : (t ~ /(^|\/)git$/ ? "o" : (t == "gh" ? "h1" : "")))
      continue
    }
    if (kind == "o") { # git -C dir -c k=v …: its options, up to the subcommand
      if (skip) skip = 0
      else if (t ~ /^(-C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--exec-path|--attr-source|--shallow-file)$/) skip = 1
      else if (t !~ /^-/) kind = (t ~ /^(commit|tag)$/ ? "c" : (t ~ /^(merge|stash|notes)$/ ? "m" : ""))
      continue
    }
    if (kind == "h1") { kind = (t ~ /^(pr|issue|release)$/ ? "h" : ""); continue }
    if (kind == "h") {
      if (pend) { if (tq[j]) mask[j] = "MSG"; pend = 0 }
      else if (!tq[j] && t ~ /^--(title|body|notes|subject|comment)$/) pend = 1
      else if (tq[j] && tpre[j] ~ /^--(title|body|notes|subject|comment)=$/) mask[j] = tpre[j] "MSG"
      continue
    }
    if (kind == "") continue
    # git commit, tag, merge, stash, notes. A word some option takes as its value is never a flag.
    if (!free) { if (pend && tq[j]) mask[j] = "MSG"; pend = 0; free = 1; continue }
    if (t == "--") { kind = ""; continue } # the rest are paths
    if (!tq[j] && msgflag(t, kind)) { pend = 1; free = 0; continue }
    # A value attached to its flag (-m"…", -am"…", --message="…") is one word: nothing to take from.
    if (tq[j] && tpre[j] !~ /^--(message|file)$/ && (tpre[j] ~ /^--(message|file)=$/ || msgflag(tpre[j], kind))) { mask[j] = tpre[j] "MSG"; continue }
    free = (t !~ /^-/ || novalue(t, kind))
  }

  first = 1 # at the start of an output line
  for (j = 1; j <= k; j++) {
    if (tsep[j] != "") {
      if (tsep[j] ~ /[<>]/) { printf " \002%s", tok[j]; first = 0 }
      else { printf "\n"; first = 1 }
      continue
    }
    x = (j in mask) ? mask[j] : tok[j]
    if (x == "" && tq[j]) x = "''" # an empty quoted word is still a word (git config k '' sets k)
    gsub(/\002/, "?", x)
    if (out == "A") gsub(/[ \t\n]/, "\001", x)
    else if (xglob) gsub(/[;&`\n]/, "\n", x)
    else gsub(/[;&|()`\n]/, "\n", x)
    printf "%s%s", (first ? "" : " "), x
    first = 0
  }
  printf "\n"
}
