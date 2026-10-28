# Validation and evidence ledger

[Home](../README.md)

## Evidence vocabulary

- **Direct local experiment:** performed in the original local research session.
- **Contributed report:** written in a user-supplied distribution; not independently
  repeated by the compiler of this handoff.
- **Owner/community feedback:** a reported observation without a retained,
  independently evaluated trace.
- **Interpretation:** a conclusion supported by the above, with limits stated.

## Local Classic AT&T / China Mobile, 27 October

Direct results:

- Native IMS registered on LTE with IR92 and VoLTE capability.
- ESP NULL + HMAC-SHA1 SA creation recovered when the built-in software provider
  was registered. An isolated namespace provided the disable/enable comparison.
- A manual outgoing call connected. The user confirmed voice. The session
  recorded 4,451 received and 4,500 sent AMR/8000 RTP packets.
- Original BlackBerry dots appeared and followed airplane-mode disconnect and
  reconnect, confirmed visually by the user.
- Windows package enable, forced reapply, restore, deliberate failure/automatic
  rollback, duplicate enable, Chinese/space-containing paths, and component
  integrity rejection were exercised.
- Native decoder self-test passed seven cases. The original auto-dial helper
  crashed before making a call and is excluded from recommended tools.

No local incoming-call success was established. Later Q20 incoming failures
were reported to the owner. There is no raw incoming-call trace in this archive.

Files:

- `evidence/cmcc-historical-public-status.txt`: selected actual PPS lines from
  historical local files; the source filenames are retained. Earlier attempts
  without `connected` remain distinguishable from the successful attempt.
- `evidence/cmcc-isolated-provider-toggle.txt`: selected original console output
  with process IDs generalized. `Invalid argument` while disabled, followed by
  no reported SA errors when enabled. `No entry` follows deletion of an SA
  whose creation failed; it is not a separate root cause.
- `evidence/berry-airplane-mode-transitions.txt`: original monitor transitions.
- RTP counts and user voice confirmation are session observations described
  here, not a raw call recording or packet capture included in the archive.

## Fresh Q20 snapshot, 28 October

The owner reconnected the Classic AT&T with China Mobile and was using it as a
hotspot for the research PC. Only read-only collection was performed during
this handoff. The actual state was LTE attached, IMS `idle`, and no dots value.
No enable/restart was performed to manufacture a fresh success snapshot.

This is compatible with the known need to reapply runtime setup after boot,
but the collection alone does not isolate the idle state's cause. It must not
be presented as a fresh registered/call-success retest. See
`evidence/q20-20261028-readonly.txt`.

## Contributed Classic Verizon / China Unicom

The supplied v1.0 archive reports native IMS registration and dots after
adapting carrier 36 and execution trust. The firmware execution policy required
additional pathtrust handling according to its notes. No new phone call was
made on that device during this handoff. The owner's broader Q20 incoming-call
feedback remains a limitation, not a per-variant diagnostic conclusion.

## Contributed Passport / China Unicom v1.1

The later section of the supplied notes reports outgoing and incoming calls,
including a normal handset caller that waited long enough to ring and answer.
It also reports restore, repeated enable, BerryOff, and injected-failure
rollback tests. Earlier sections in the same notes say voice had not yet been
tested; these reflect the earlier stage, not the final reported result.

No Passport was connected for an independent local retest in this handoff.
The candidate incoming changes and contradictions are reviewed in
[incoming calls](03-incoming-calls.md). The report of provider disable
restarting io-pkt is retained as an important portability warning.

## Local Z30 STA100-3 negative test, 28 October

SIM was READY, network locks were UNLOCKED, radio power was ON, and LTE was
already enabled. A temporary `configure_rats` request selected only LTE; the
published state confirmed that selection. Four observations remained in LTE
search with no attachment, and the LTE capability mask stayed `4104` (B4/B13).

The original all-technology selection was restored and its snapshot checksum
matched exactly. DCA archive comparison returned 0. No IMS/APN/module/NV or
baseband modification was made. See `evidence/z30-lte-only-scan.txt`.

This supports a radio-frequency/attachment limitation for the available
network, before IMS can be tested. It is not an RF teardown or proof about
every hypothetical NV unlock. A Z30 label alone does not establish its bands.
