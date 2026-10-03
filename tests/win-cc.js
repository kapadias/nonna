// Scratch (#45, never merged): a command as Claude Code hands it to Git Bash. Its Bash tool spawns
// [shell, "-c", "-l", "... && eval <command, quoted> && pwd -P >| <file>"]; the quoting below is copied
// from its bundle (shell-quote's quote, and '…' for a heredoc or a quoted newline).
const { spawnSync } = require("child_process");

const quote = (q) =>
  q
    .map((K) => {
      if (K === "") return "''";
      if (/["\s\\]/.test(K) && !/'/.test(K))
        return "'" + K.replace(/(['])/g, "\\$1") + "'";
      if (/["'\s]/.test(K)) return '"' + K.replace(/(["\\$`!])/g, "\\$1") + '"';
      return String(K).replace(
        /([A-Za-z]:)?([#!"$&'()*,:;<=>?@[\\\]^`{|}])/g,
        "$1\\$2",
      );
    })
    .join(" ");
function heredoc(A) {
  if (
    /\d\s*<<\s*\d/.test(A) ||
    /\[\[\s*\d+\s*<<\s*\d+\s*\]\]/.test(A) ||
    /\$\(\(.*<<.*\)\)/.test(A)
  )
    return false;
  return /<<-?\s*(?:(['"]?)(\w+)\1|\\(\w+))/.test(A);
}
function multiQuoted(A) {
  return (
    /'(?:[^'\\]|\\.)*\n(?:[^'\\]|\\.)*'/.test(A) ||
    /"(?:[^"\\]|\\.)*\n(?:[^"\\]|\\.)*"/.test(A)
  );
}
function wrap(A) {
  if (heredoc(A) || multiQuoted(A)) {
    const Y = `'${A.replace(/'/g, `'"'"'`)}'`;
    return heredoc(A) ? Y : `${Y} < /dev/null`;
  }
  return quote([A, "<", "/dev/null"]);
}

const cases = [
  "printf '<%s>' a\rb",
  "printf '<%s>' 'a\rb'",
  "printf '<%s>' \"a\rb\"",
  "echo A \r#; echo RAN",
  "gi\rt --version",
  "echo A \\\r\necho RAN",
  "printf '<%s>' \"a\rb\nc\"",
  "cat <<'EOF'\na\rb\nEOF",
];
for (const bash of process.argv.slice(2)) {
  for (const c of cases) {
    const P = [
      "shopt -u extglob 2>/dev/null || true",
      `eval ${wrap(c)}`,
      "pwd -P >| /tmp/cc-cwd",
    ].join(" && ");
    const r = spawnSync(bash, ["-c", "-l", P], { encoding: "buffer" });
    const show = (b) =>
      JSON.stringify((b || Buffer.alloc(0)).toString("latin1"));
    console.log(
      `probe E17: ${bash}: eval of ${JSON.stringify(c)} as ${JSON.stringify(wrap(c))} -> ${show(r.stdout)} ${show(r.stderr).slice(0, 120)}`,
    );
  }
}
