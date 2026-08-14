# Test stubs

Executable stand-ins for the vendor CLIs. Each one prints the argv it received
and, when asked, the stdin it received, in a form the test harness can assert
on. Nothing here contacts a vendor, so the suite runs with no credentials, no
network, and no subscription spend.

The distinction matters: assertions over a pure "build the argument list"
function would miss stdin damage, stdout/stderr separation, exit-status
propagation, and a probe failure aborting the caller. Those are behaviours of
the script as a running program, so the harness has to actually run it against
executables.

What this suite cannot check is whether a real CLI still *means* what its flags
say — a vendor can keep accepting `--model X`, exit zero, and quietly use a
different model. That failure exits zero and passes every assertion here. It is
the live canary's job, not this suite's.
