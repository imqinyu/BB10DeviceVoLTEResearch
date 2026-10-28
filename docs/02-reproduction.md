# Reproduction guide and rollback boundaries

[Home](../README.md)

This is a research sequence, not a generic install script. Use the matching
variant only after verifying the hardware, OS, carrier and execution policy.
The root method and a working root SSH key are prerequisites.

## Gate 1: verify LTE and the actual SIM

Read the radio public object and the SIM's home PLMN. A 4G menu option is not
proof of a compatible radio band. The Z30 STA100-3 experiment could explicitly
select LTE but could not attach on the available China Mobile network.

The original profiles are bound to:

- `CLASSICATT`, 10.3.3.3216, China Mobile 460-00;
- `CLASSICVZW`, 10.3.3.3216, China Unicom 460-01;
- `WINDERMERE4ROW`, 10.3.3.3216, China Unicom 460-01.

The observed io-pkt POSIX checksum was `1240815568`, length `945248` bytes.
SHA-256 fingerprints are in `evidence/firmware-fingerprints.json`. Do not copy
the hardware check to a different model merely to make an installer continue.

## Gate 2: verify execution trust and save this device's state

Root UID and permission to execute an unsigned image are separate checks.
Read [portability](04-portability.md) before loading a module.

Back up each target file, whether it originally existed, its mode/owner, the
current `cdsc_xml` value and referenced XML, IMS running state, and any
engineering/provisioning values you will change. Store backups on persistent
storage and copy them privately to the computer. Never restore another
device's backup.

The original China Mobile 1.0 package put its backup under `/var/tmp`; that
path is not dependable across boots. The supplied Verizon and Passport
derivatives use persistent `/var/etc` state. This archive retains the original
1.0 package for provenance, not as an endorsement of that backup location.

## Configuration files

`configs/dca-sources/` contains the six file examples relative to
`/var/dca/sources/`:

1. `ims/services/carrier_config/ims/ims`
2. `ims/services/carrier_config/radio_common/cellular_protocol_configuration`
3. `ims_defaults/services/carrier_config/radio_common/cellular_protocol_configuration`
4. `omadm/services/carrier_config/radio_common/cellular_protocol_configuration`
5. `test/services/carrier_config/radio_common/cellular_protocol_configuration`
6. `test/services/carrier_config/radio_qct/ims`

The radio-common payload is:

```text
@cellular_protocol_configuration
voice_domain_preference_EUTRAN:n:3
ue_usage_setting::voice_centric
wcdma_to_lte_ps_ho_support:b:false
```

Publish with `dca -s -a /pps`, then inspect both the published `ims/ims` and
`radio_common/cellular_protocol_configuration` objects. Source files are
overwritten by these examples; preserve all original attributes in backup.

## Carrier data configuration

Use a copy of the device's own carrier XML as the base. The supplied examples
are under each variant's `payload/` directory:

- China Mobile: carrier 404, internet APN `cmnet`, dedicated IMS APN `ims`;
- China Unicom: carrier 36, internet APN `3gnet`, dedicated IMS APN `ims`.

The Passport contribution notes an original XML difference from the Classic,
including an `a_gps` alias. Preserve device-local differences when porting.
The XML and its parent directories must be accessible to the cellular service;
root being able to read a file does not establish that access.

The runtime selector has the form:

```sh
echo 'cdsc_xml::/path/readable/by/cellular-service/carrier-copy.xml' >> /pps/services/cds/cnice/status_persistent
```

This is an example, not a command to run with a literal placeholder path.

## Crypto provider and engine order

On the matching, already verified stack, the module entry accepts `status`,
`enable`, or `disable`:

```sh
mount -T io-pkt -o status /trusted/path/devnp-volte-swcrypto.so
mount -T io-pkt -o enable /trusted/path/devnp-volte-swcrypto.so
```

`status` does not register/unregister crypto, but invoking it still asks the
loader to load/enter a native module. Do not include it in a supposedly
configuration-free evidence collector.

Keep the same trusted module path. Enable the provider before starting the
IMS engine. The original engine identity was:

```sh
on -d /radio/bin/ims_rrm -U 453:31,80,387,427,521,1001
```

The historical scripts set `LD_LIBRARY_PATH` explicitly; use the variant
script as the exact reference. Stop/restart operations can disrupt calls or
hotspot use, so the evidence collector does not perform them.

## Verify each layer separately

1. Radio attached to LTE.
2. Dedicated IMS bearer and P-CSCF discovered.
3. IMS `status=connected`, `default_ran=LTE` (case-insensitive), `IR92`, `VoLTE`.
4. Outgoing call setup and two-way audio.
5. Incoming call reaches the device, rings, can be answered, and has two-way audio.
6. Recovery after airplane mode and reboot, if tested.

The BlackBerry dots alone prove none of steps 1–5.

## Rollback

Stop only the monitor and IMS process involved in the experiment, restore the
original files and original missing-file state, restore `cdsc_xml` and any
engineering/user settings, re-aggregate DCA, and restore the previous process
state. Preserve file ownership and permissions.

Do not blindly call the provider's `disable` entry. The Passport contribution
explicitly omits it because of an observed network-stack restart. Rollback to
pre-tool configuration is not necessarily factory state, and does not imply
every runtime capability was unloaded.
