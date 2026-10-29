# Experimental VoLTE on BlackBerry 10

**Research handoff, 28 October 2026.** [中文说明](README.zh-CN.md)

**NOTICE**
If you want a ready-to-use solution, check out Oleksandr's BB10 VoLTE Addon [here](https://github.com/bb10root/bb10-volte)

This repository collects the source, configuration changes, selected evidence,
and limitations from experiments on BB10 **10.3.3.3216**. It is intended to let
other researchers reproduce and investigate the work, including Oleksandr,
whose [BB10 root research](https://bb10.root.sx/) made privileged access possible.
It is not a root installer or a universal carrier unlock.

## Results and evidence level

| Device / carrier | LTE / IMS | Outgoing voice | Incoming voice | Evidence |
|---|---|---|---|---|
| Classic AT&T (`CLASSICATT`), China Mobile 460-00 | Registered in the original session | User-confirmed call; session recorded bidirectional RTP | **Not established. Q20 incoming-call failures have been reported.** | Direct local experiment, 27 October |
| Classic Verizon (`CLASSICVZW`), China Unicom 460-01 | Registration reported | Not independently verified in this handoff | Not established; do not infer support from registration | Contributed distribution and notes |
| Passport (`WINDERMERE4ROW`), China Unicom 460-01, v1.1 | Registration reported | Reported working | **Reported working with a normal handset caller** after additional changes | Contributed distribution and test notes; not independently repeated here |
| Z30 STA100-3, China Mobile 460-00 | No LTE registration; advertised LTE bands B4/B13 | Not tested | Not tested | Direct local negative test, 28 October |

An IMS `connected` value is not a complete call test. Outgoing calls, incoming
calls, bidirectional audio, and the status-bar BlackBerry dots are separate
observations. **Do not describe the Q20 result as fully working incoming and
outgoing VoLTE.** See [validation](docs/05-validation-and-evidence.md).

## Main findings

1. DCA overrides can declare MMTel voice on LTE and select the common IMS engine
   with the IR92 profile.
2. The original China Mobile carrier configuration aliased IMS to the internet
   service. A separate `ims` APN with PCO P-CSCF discovery was required.
3. The local China Mobile experiment reached SIM-based IMS authentication but
   failed to install ESP NULL + HMAC-SHA1 security associations, with error 22.
   Its boot script disabled the built-in software crypto provider. Registering
   that **existing** provider resolved the failure; no firmware binary patch or
   modem NV edit was used.
4. The original BlackBerry status-bar dots have a separate Navigator PPS switch.
   A small native monitor can use them as a VoLTE registration indicator. This
   does not restore BBM or BIS.
5. The contributed Passport work adds execution-trust/addon handling, an
   engineering voice-domain override, and incoming-call provisioning changes.
   Its reported provider-unload failure is a significant portability limit.

## Start here

- [Short technical handoff for Oleksandr and other researchers](HANDOFF.md)
- [Technical findings and experiment sequence](docs/01-findings.md)
- [Manual reproduction and rollback boundaries](docs/02-reproduction.md)
- [Incoming calls: Q20 limitation and Passport changes](docs/03-incoming-calls.md)
- [Execution trust, persistence, and packaging pitfalls](docs/04-portability.md)
- [Validation matrix and evidence descriptions](docs/05-validation-and-evidence.md)
- [Build and static-analysis guide](docs/06-build-and-analysis.md)
- [Open questions for further research](docs/07-open-questions.md)
- [Sources, attribution, and distribution provenance](docs/08-provenance.md)

## Repository map

| Path | Contents |
|---|---|
| `src/` | Exact baseline native C sources from the locally tested China Mobile package |
| `prebuilt/classic-att-cmcc/` | Matching supplied native module and indicator binaries |
| `configs/` | The six DCA source-file examples, retaining device-relative paths |
| `variants/` | Extracted source, device scripts, Windows launchers, and carrier XML from all three distributions |
| `distributions/` | The three original, byte-for-byte distribution ZIPs; their legacy UI and notes are Chinese |
| `evidence/` | Selected/sanitized historical outputs and a fresh read-only Q20 snapshot |
| `tools/` | Read-only evidence collection, build, validation, and local static analysis |
| `experiments/` | An explicitly isolated SA diagnostic; no automatic deployment |

The extracted variant scripts preserve the received implementations, including
known limitations. They are not silently generalized to other hardware or
carriers. Read the portability notes before using them.

## Sharing and reproducing

No SSH keys, device passwords, SIM PINs, IMS authentication material, full SIP
captures, individual device backups, BlackBerry firmware executables, or SDK
libraries are included. The root method is referenced, not redistributed.

Run `python tools/validate_release.py .` before sharing a modified checkout.
See [publication notes](PUBLICATION.md) for repository/release preparation and
[NOTICE](NOTICE.md) for provenance and licensing status. The archive has not
been uploaded to GitHub by this handoff.
