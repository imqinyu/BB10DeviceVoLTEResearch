# Open questions and useful next experiments

[Home](../README.md)

## Incoming calls on Classic/Q20

This is the highest-priority functionality gap. Determine where MT calls fail
on a known Q20/carrier combination before copying Passport settings. A single
controlled incoming attempt should distinguish: no INVITE; INVITE rejected;
ringing followed by remote CANCEL; answer failure; or missing media. Compare
one configuration variable at a time and keep subscriber/authentication
material out of public traces.

## Native startup integration with the root environment

Oleksandr's root work and its supported addon/startup mechanisms are the
appropriate integration point. This handoff does not define a new boot hook.
An eventual integration should account for when io-pkt and the radio are
ready, carrier/SIM changes, execution trust, idempotent provider registration,
and safe configuration rollback. Enabling the provider at a repeatable stage
may avoid the need to restart the full network stack.

## Provider lifecycle

Why does provider disable succeed in the original controlled stack but restart
the Passport's stack in the contributed report? Reproduce without active
subscriber traffic first. Investigate active sessions, reference lifetimes,
driver unload/re-entry and multiple module images. The current evidence does
not isolate the cause. Do not infer from a module's `status` result alone that
unregistering all of its algorithms is safe.

## Generalizing configuration responsibly

- Map DCA source priority instead of overwriting four sources indefinitely.
- Derive a carrier XML from the device's original rather than replacing unrelated
  service definitions with a different model's copy.
- Distinguish IMS registration prerequisites from incoming-call provisioning.
- Normalize public status casing in future monitors and add lowercase tests.
- Make durable backups the default; migrate away from the original `/var/tmp`
  backup location without overwriting a valid earlier baseline.
- Review the literal code against later notes: a claimed minimum restart wait
  is not implemented by a loop that returns early after a shorter sleep.

## Validation still missing

The local work did not establish a comprehensive incoming-call matrix, SMS,
long-duration stability, battery/performance impact, inter-cell handover, IMS
re-registration under load, multiple-SIM/carrier behavior, or universal boot
recovery. Do not extrapolate from a successful outgoing test or the dots.

## Hardware limits

The Z30 STA100-3 result shows why LTE attachment is the first gate. It only
advertised B4/B13 and did not attach on the available China Mobile network.
The experiment provides no evidence for adding unsupported RF bands with a
DCA or engineering-menu edit. Treat an RF unlock claim as a separate research
project requiring its own device-specific evidence.
