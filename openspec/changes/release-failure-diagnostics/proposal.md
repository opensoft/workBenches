# Safe release failure locations

The hosted v1.6 fixture run passed 11 suites but failed fresh-install. Private
subprocess logs are intentionally deleted; the public report lacked a location.
Extract only known exception classes and the line number in the two acceptance
drivers from the bounded private log tail. Never publish messages, full paths,
tracebacks, commands, credentials or transcript bytes. Keep all gates unchanged.

A real failing child and a credential-bearing traceback fixture verify that only
allowlisted identifiers survive. Rerun hosted fixtures to diagnose the failure.
