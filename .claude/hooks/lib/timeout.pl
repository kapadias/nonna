#!/usr/bin/env perl
# Process-group timeout for nonna_run_tests where timeout(1) is absent (macOS, Git Bash). ADR-0018
# moved it out of an inline `perl -e` so the directory validator can follow the plugin's commands; the
# logic is unchanged. Usage: perl timeout.pl <seconds> <command> [args...]. Forks the command into its
# own process group; on the one-second alarm it sends TERM to the group, waits a second, then KILL, and
# exits 124, so a child that ignores TERM is still felled and a timed-out run is never mistaken for a
# pass. Otherwise it relays the child's exit status (128 + signal when the child was signalled).
my $secs = shift;
my $pid = fork;
die "fork: $!" unless defined $pid;
if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
$SIG{ALRM} = sub { kill "TERM", -$pid; sleep 1; kill "KILL", -$pid; exit 124 };
alarm $secs;
waitpid($pid, 0);
exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
