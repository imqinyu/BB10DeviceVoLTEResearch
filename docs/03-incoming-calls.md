# Incoming calls: an unresolved Q20 boundary and the Passport contribution

[Home](../README.md)

## What is established

The local Classic/China Mobile session established an outgoing call, not
incoming service. During this handoff the owner reported feedback that Q20
could call out but could not receive calls. The affected Q20 variants, carrier
accounts and failure traces have not been enumerated; this feedback must not
be generalized to every Classic or every network.

The supplied Passport 1.1 notes report outgoing calls and a normal handset
incoming call that rang, was answered, and stayed connected. This is a
contributed test report, not a local retest on a Passport during this handoff.

## Additional Passport changes

### Engineering voice-domain override

The contribution identifies the metadata file:

`/base/etc/escreens/ims/volte/volte.meta`

and the setting:

```text
/pps/services/escreens/config
voice_domain_preference_EUTRAN_override::5
```

Its reported enumeration is: 2 = no override, 3 = CS only, 4 = CS preferred,
5 = IMS PS only, 6 = IMS PS preferred (1 is an empty entry).

**This enumeration is not the same as DCA's**
`voice_domain_preference_EUTRAN:n:3`. The two values must not be substituted
for one another. The Passport script backs up and restores the engineering
setting. This setting was not tested as a fix for the local Q20 incoming issue.

### Carrier user provisioning

In `/var/ims/carrier/imsconfig_036.xml`, the contributed script changes:

```xml
<AllowVoLteProvisioning>disabled</AllowVoLteProvisioning>
```

to `enabled`, preserving the file's IMS/radio ownership and mode. The observed
public counterpart is `allowVoLteProvisioning:n:1`.

The notes say incoming INVITEs did not reach the device before this change and
did afterwards. This is a useful lead, but the archive does not contain raw
SIP traces establishing a universal network-side cause. The local China
Mobile device registered with this flag at 0; that only shows it was not
required for **registration**, not that it was unnecessary for incoming calls.

### IR92 compatibility settings

The Passport source creates an `ims/ir92` DCA override including:

```text
@ir92
UsePreconditions:n:0
SMS_Format::3GPP
amr_modeset_list::7
amrwb_modeset_list::2
```

These values belong to that contributed configuration. Do not assume they
are a universal codec/provisioning recommendation.

The final Passport notes explicitly say a successful call still included
183/PRACK, so disabling preconditions was **not isolated as the sole fix**.
Earlier script comments attribute incoming cancellation more strongly to
preconditions; the later, narrower conclusion takes precedence.

## Distinguish device rejection from caller cancellation

The Passport notes describe early tests in which the calling side sent CANCEL
roughly 0.45–0.7 seconds after ringing. A normal handset willing to wait longer
subsequently rang and connected. A caller-side CANCEL is different from the
device rejecting an INVITE. The claimed successful sequence was approximately:

```text
14:34:47  ringing response
14:35:01  answer / ACK, call established
14:35:11  call ended
```

Those times are a summary of contributed notes, not a raw capture included in
this archive. A local `incoming_ready()` function only checks configuration
flags; it does not itself prove an incoming call can be received.

## What should be investigated on Q20 next

1. Establish an outgoing baseline and collect a real incoming-call attempt.
2. Determine whether an INVITE reaches the handset at all.
3. If it arrives, distinguish routing/domain selection, alerting, CANCEL,
   answering, preconditions, SDP negotiation, and media failure.
4. Compare the device-local carrier user setting and engineering enumeration.
5. Change one variable at a time, preserving the original state.

Do not copy `imsconfig_036.xml` to a China Mobile device: carrier 36 is Unicom,
whereas the local Mobile configuration is carrier 404. The device may create
its carrier-specific user settings only after the first engine start.

The Passport notes also mention 403/AUTS and restart timing. A 403 response
alone does not diagnose one particular AKA/IPsec fault. Its text says to wait
15 seconds, while the actual `stop_ims()` implementation waits up to 15 seconds
for process exit and then sleeps two seconds once it exits. Preserve this
code/document discrepancy when planning a controlled timing experiment.
