#!/bin/sh
# Diagnostic only. Requires an existing isolated stack with no physical NICs.
# Synthetic test keys below are public all-zero placeholders, not SIM/IMS keys.
set -e
namespace=/var/tmp/volte-isolated
module=${1:-}
test -n "$module" -a -f "$module" || { echo 'Supply a trusted module path.'; exit 2; }
test -e "$namespace/dev/socket" || { echo 'Dedicated isolated namespace is not running.'; exit 2; }
export SOCK=$namespace
# Refuse an instance containing a non-loopback interface.
interfaces=$(ifconfig -l)
test "$interfaces" = lo0 || { echo 'Refusing: namespace is not loopback-only.'; exit 2; }
probe() {
    setkey -c <<'SA'
add 2001:db8:bb10::1 2001:db8:bb10::2 esp 0x00bb1023 -m transport -lh 10 -ls 5 -E null -A hmac-sha1 0x0000000000000000000000000000000000000000;
delete 2001:db8:bb10::1 2001:db8:bb10::2 esp 0x00bb1023;
SA
}
restore() {
    trap - 0 INT TERM HUP
    mount -T io-pkt91 -o enable "$module"
}
trap restore 0
trap 'exit 1' INT TERM HUP
echo 'ISOLATED SOFTWARE PROVIDER DISABLED (expected NULL SA failure)'
mount -T io-pkt91 -o disable "$module"
probe
echo 'ISOLATED SOFTWARE PROVIDER ENABLED (expected NULL SA success)'
mount -T io-pkt91 -o enable "$module"
probe
echo 'Read the setkey output; its exit code alone did not detect errors in the original test.'
