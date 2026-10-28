# Build and local analysis

[Home](../README.md)

## Native build

The local build used the BB10 10.3 NDK ARMv7 toolchain, host package
`host_10_3_1_12` and target `target_10_3_1_995/qnx6`. Supply your own SDK paths;
the SDK is not redistributed.

```powershell
./tools/Build.ps1 -NdkHost 'C:/your-ndk/host_10_3_1_12/win32/x86' `
  -NdkTarget 'C:/your-ndk/target_10_3_1_995/qnx6'
```

Output is placed under ignored `build/armv7/`, not over the archived binaries.
The compiler flags are ARMv7 Thumb, `-O2 -Wall -Wextra -Werror`; the module is
`-shared -fPIC`, the monitor `-fPIE -pie` linked with `-lpps`.

During handoff validation, rebuilding both baseline sources with those NDK
packages produced SHA-256 hashes exactly matching the preserved baseline
prebuilt files. This check applies to that source/toolchain combination, not
to every contributed variant or compiler.

The provider exports an `iopkt_drvr_entry` structure with version 1, flags 0,
and an entry callback `(void *handle, void *self, char *options)`. Its external
symbol ABI is specific to the observed io-pkt build. A matching OS string is
not by itself a guarantee that another stack exports the same ABI.

Prebuilt binaries are included only for the supplied profiles. Rebuilding is
not a reason to bypass their model or component checks.

## Indicator self-test

On a device/path already permitted to execute this component:

```sh
/trusted/path/volte-berry --self-test
/trusted/path/volte-berry --check
```

The first only exercises parsing. The second reads IMS and Navigator state;
exit 0 means the desired and actual dots state agree, **not** necessarily that
VoLTE is connected. For example, disconnected/off can also agree. Read its
`VoLTE_connected` field.

The baseline monitor is preserved unchanged, including the uppercase LTE
comparison. Review the known limitations before using it on lowercase output.

## Static analysis without redistributing firmware

Obtain each firmware executable from your own device. Use the recorded hashes
to identify the examined build. Full disassemblies and vendor executables
were deliberately excluded from this public handoff.

```sh
python -m pip install -r tools/requirements-analysis.txt
python tools/thumb_inspect.py path/to/own/io-bb 0x133e8 0x13678
python tools/thumb_inspect.py path/to/own/ims_rrm --find IMS_platform
```

The helper maps ELF virtual addresses through PT_LOAD segments, decodes Thumb
instructions, and annotates simple PC-relative string loads. It is a local
inspection aid, not a complete decompiler or a patch generator. Addresses and
inferences must be checked against the matching build and instruction mode.

## Isolated crypto comparison

`experiments/ipsec/probe-isolated.sh` requires an **already running dedicated**
io-pkt instance 91, namespace `/var/tmp/volte-isolated`, no physical interfaces,
and a trusted module path supplied as an argument. It refuses the default
namespace. It does not start/copy firmware, modify a live network interface,
or install IPsec traffic policies. Synthetic documentation IPv6 addresses,
zero test keys, short lifetimes and explicit deletion are used.

The historical experiment started the isolated stack with:

```text
io-pkt copy -i91 -ptcpip prefix=/var/tmp/volte-isolated,ipsec,random,stacksize=4864
```

This is a description of the experiment, not an executable command or a
bundled firmware copy. Existing root/trust setup must permit such an instance.
The original private test copy was stopped after the experiment.

## Non-mutating collection

```powershell
./tools/Collect-PublicEvidence.ps1 -Key "$env:USERPROFILE/.ssh/your-root-key" `
  -OutFile './evidence/my-device-readonly.txt'
```

Only allowlisted model/OS/carrier/radio/IMS configuration fields are emitted.
The collector does not call `dca`, `mount`, `pathtrust`, write PPS, restart
services, or dial. It can be used while the phone is providing a hotspot.
It does not export full private IMS or SIM objects or firmware binaries.
