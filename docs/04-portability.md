# Execution trust, persistence, and packaging limitations

[Home](../README.md)

## Root does not imply every writable path is executable

The three distributions use different execution environments:

| Variant | Component location | Reported execution mechanism |
|---|---|---|
| Local Classic AT&T / Mobile | `/var/tmp/bb10-volte` | Native components executed on the experimental device |
| Contributed Classic VZW / Unicom | `/var/tmp/bb10-volte` | `pathtrust`, including a filesystem-level fallback |
| Contributed Passport / Unicom 1.1 | `/var/addons/bb10-volte-unicom/data` | Addon `MANIFEST`, `perms`, `trusted`, and one installation reboot |

The VZW contribution uses `pathtrust "!<file>"` for file trust and falls back
to `pathtrust <file>` if its self-test still fails. The latter trusts the
containing filesystem for execution; it is not a change limited to the
named executable. These runtime marks were reported to disappear on reboot.

The Passport notes report that both forms returned success but execution from
`/var/tmp` still failed. Its addon metadata approach was needed instead.
Already trusted binaries/metadata were not repeatedly rewritten, because
rewriting could invalidate their trust for the current boot. This is a
reported root/firmware-environment distinction, not proof that every Passport
requires the same approach. The original root distribution is not bundled.

## Persistence

Separate four kinds of state:

1. Persistent DCA/carrier user files.
2. Runtime PPS selectors such as `cdsc_xml` and engineering overrides.
3. Running IMS/indicator processes and registered crypto providers.
4. Execution-trust state, which depends on the root environment.

The first China Mobile package used `/var/tmp` for both components and backups.
Later contributions moved backups to `/var/etc`, and Passport components to
`/var/addons`. A historical package surviving on the PC does not prove its
device-side backup survived reboot. No fully integrated boot autostart is
claimed by this handoff.

## Provider unloading is a device-specific risk

The local isolated-stack test demonstrated reversible provider registration.
The local Classic also survived its tested workflow. The Passport report,
however, describes a network-stack restart on provider disable, and its
restore routine intentionally leaves the provider loaded until reboot.

The exact reason for that failure has not been isolated. Possible interactions
with active crypto users, driver lifecycle, and multiple loaded images remain
research questions. The baseline `disable` implementation unregisters all
algorithms belonging to that provider; it is not a per-IMS disable switch.

Keep this distinction when merging rollback logic. A successful configuration
restore is not necessarily a full runtime-provider restore.

## PPS and userland differences encountered

- `slay` returned a nonzero status after actually terminating the process in
  this environment. Scripts were changed to check whether it remained alive.
- An external `printf`, `tr`, and `rmdir` were not reliably present on the
  observed shell path. The scripts use QNX ksh `print -r --` and existing tools.
- Some PPS objects are larger than small utility read buffers. `cat object |
  filter` worked where directly opening the object with a filter failed with
  `Message too long`.
- Windows PowerShell 5.1 needs UTF-8 BOM for scripts containing Chinese text.
- A parent PowerShell 7 environment polluted module lookup for Windows
  PowerShell 5.1. The launcher imports modules from its own `$PSHOME`.
- OpenSSH compatibility options were needed for BB10's legacy RSA/SHA1 SSH
  server. Key authentication is still device-specific; no keys are bundled.
- Newer SCP clients may need legacy SCP mode (`-O`).
- `setkey` printed meaningful errors while its shell exit status remained 0.
  Inspect output and successful cleanup; an exit code alone is insufficient.
- `default_ran` was observed as both `LTE` and `lte`. Shell checks in later
  variants are case-insensitive, but the preserved C monitor sources still
  compare uppercase exactly. This can create a false negative for the dots.

## Source/binary provenance

The root `src/` and `prebuilt/classic-att-cmcc/` are the baseline local package.
Every variant retains its own source and binary snapshot. Do not assume that
rebuilding one variant produces a byte-identical binary to another, or that a
source comment proves the runtime behavior of a contributed binary.

The preserved scripts are experimental implementations. In particular,
readiness flags for incoming calls are local configuration checks, backup
locations differ, and a helper being idempotent is not proof of general
portability. No universal installer has been produced by this handoff.
