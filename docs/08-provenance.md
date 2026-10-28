# Sources, attribution, and provenance

[Home](../README.md)

## Research origin

- Oleksandr's [BlackBerry 10 root and security research](https://bb10.root.sx/)
  supplied the prerequisite access mechanism used by the owner. This archive
  does not redistribute the root implementation, its downloads, or credentials.
- The device owner supplied the original DCA approach, devices, SIM, physical
  call/indicator confirmations, and later Q20 incoming-call feedback.
- The local Classic/China Mobile and Z30 experiments were performed through
  the owner's workstation with Codex assistance. The source and documentation
  in this archive are a research handoff, not an endorsement by BlackBerry,
  QNX, any carrier, or Oleksandr.
- The Classic VZW/Unicom and Passport/Unicom packages were contributed to the
  owner by other researchers. Their names/handles were not established here;
  attribution should be completed with the contributors before assigning them
  a specific name or a new license.

## Original distribution fingerprints

`provenance.json` records original archive hashes and the distinction between
locally tested and supplied material. `distributions/` retains exact original
bytes. `variants/` extracts the relevant C sources, native payloads, XML,
device management scripts and Windows launchers without rewriting them.

The legacy packages contain Chinese-language UI/notes. The English documents
in this repository explain the results and their limits for an international
research audience. No new generic installer is implied by their inclusion.

## Public references

- [BB10 root research](https://bb10.root.sx/): prerequisite access and execution
  trust context. Root access and execution policy are separate issues.
- [QNX io-pkt documentation](https://www.qnx.com/developers/docs/6.6.0.update/com.qnx.doc.neutrino.utilities/topic/i/io-pkt.html):
  network-stack instances and namespaces; consult the matching SDK/platform.
- [BlackBerry OS 10.3.3 Security Target](https://www.commoncriteriaportal.org/nfs/ccpfiles/files/epfiles/383-4-391%20ST%20v1.10.pdf):
  printed page 4, PDF page 12, lists Z30 STA100-3 LTE B4/B13 and other variants.
- [MIIT mobile spectrum information](https://wap.miit.gov.cn/jgsj/wgj/kpzs/art/2021/art_9105abf8095d49bd9065c1b6ebb06d2a.html):
  operator frequency information, with the page's stated April 2024 update.

Protocol/configuration conclusions primarily come from the inspected device
and reported experiments, not from claims that archived forum advice is
universally correct. The static address for `update_bb_service` applies only
to the examined local `io-bb`; that executable is not included.

## Privacy and material excluded from publication

Export is based on an explicit file/field selection. It excludes:

- SSH/private keys, phone passwords and SIM PINs;
- IMSI, ICCID, IMEI, PIN/serial/unique device identities, personal phone numbers;
- private IMS status, AKA material, IPsec keys/SAs, complete SIP and RTP captures;
- individual backups, raw debug dumps, full disassemblies and SDK libraries;
- BlackBerry `ims_rrm`, io-pkt, `io-bb`, and other firmware executable copies.

Historical public state lines and a few individually reviewed synthetic or
status-only logs are retained. An allowlist-based read-only collector is
included for future contributions. The automated release validator also
checks nested ZIPs, but does not replace a human review of newly added data.
