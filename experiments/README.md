# Experimental helpers

[Home](../README.md)

`ipsec/probe-isolated.sh` is a guarded wrapper around the historical isolated
provider-toggle experiment. Its shell syntax was checked against the connected
QNX shell during handoff, but this newly guarded wrapper was **not executed**
against a new isolated stack during handoff. Historical evidence is in
`evidence/cmcc-isolated-provider-toggle.txt`.

It requires a separate, existing, loopback-only namespace and does not start a
stack, copy firmware, select RF bands or affect IMS on the primary stack.
Do not change `io-pkt91` to the primary instance to work around a failed guard.
`setkey` error text must be examined even if the process exit status is zero.

The baseline module's `disable` entry is intentionally exercised only in this
dedicated experimental instance. The Passport contribution reports a failure
when using it on a primary stack with real traffic.
