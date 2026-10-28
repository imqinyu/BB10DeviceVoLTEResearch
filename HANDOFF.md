# Technical handoff for Oleksandr and BB10 researchers

[Full overview](README.md) · [中文概览](README.zh-CN.md)

The main local result is **native outgoing VoLTE on a Classic AT&T with China
Mobile**, using the existing BB10 IMS engine and software crypto implementation.
It did not require a modem NV change or a firmware binary patch. Q20 incoming
voice remains a reported failure/validation gap. A separately supplied Passport
Unicom v1.1 port reports both incoming and outgoing calls after extra changes.

## The most useful technical lead

The Classic's startup script loads `devnp-sbgse_drv.so` with
`disable_swcrypto=1`. The IMS network selected ESP NULL + HMAC-SHA1; the device
failed SA installation with PF_KEY error 22. Synthetic NULL SA creation worked
in an isolated stack, stopped working after software-provider unregister, and
worked again after register. Enabling the existing provider on the primary
Classic stack allowed IMS registration and a real outgoing call.

`src/devnp-volte-swcrypto.c` is a small io-pkt entry shim around `swcr_id`,
`swcryptoattach(0)` and `crypto_unregister_all()`. It contains no cipher code or
packet hook. The baseline C sources were rebuilt during this handoff and both
output hashes exactly matched the preserved baseline prebuilt files.

**Important:** the contributed Passport report says provider disable restarts
its io-pkt. Its restore script intentionally does not unload the provider. That
lifecycle issue needs investigation before integrating a general boot service.

## Other results worth reusing

- Six DCA examples: `configs/dca-sources/`, including MMTel/LTE, IR92, PCO and
  the common native IMS platform.
- Dedicated IMS APN examples in each variant, retaining the normal internet
  APN. The local carrier 404 originally aliased IMS to internet.
- Independent Navigator switch for the original BlackBerry dots:
  `/pps/system/navigator/status/bb_service`, `dat.bb_service.state=on/off`.
  This is presentation, not a BIS/BBM authentication result.
- Passport 1.1 adds `AllowVoLteProvisioning=enabled`, an engineering voice-domain
  override and IR92 compatibility settings. Those are candidate leads for the
  incoming-call gap, not yet a proven Q20 fix.
- Root/trust differs by setup: the supplied VZW variant uses pathtrust; the
  Passport variant uses persistent addon metadata and an installation reboot.

## Where root-framework integration could help

An existing supported addon/startup mechanism could register the provider once
after the correct io-pkt instance is ready, restore the runtime carrier selector,
and supervise the native engine/indicator. This archive does not install such
a hook. It preserves device-specific scripts instead of declaring a universal
launcher.

The original China Mobile package's `/var/tmp` backup path is a known weakness;
later variants use `/var/etc`. The preserved C dots monitor also needs a future
case-insensitive LTE comparison: current Q20 output was lowercase `lte`.

## Evidence and boundaries

The original local outgoing call was confirmed by the owner and had recorded
bidirectional RTP. The fresh Q20 snapshot was read-only while the phone supplied
the PC's hotspot: LTE was attached but IMS was idle. We deliberately did not
restart services to turn that snapshot into a new success claim.

The Passport and VZW reports are supplied contributions, not independently
repeated device tests in this handoff. Raw auth/SIP logs, device identities,
private backups and vendor executables were excluded. Source snapshots,
distribution hashes, reviewed evidence and analysis tools are included so the
work can be checked without redistributing firmware.
