#!/bin/sh
# BB10 VoLTE Easy for China Unicom; target Classic VZW (CLASSICVZW) / BB10 10.3.3.3216.
# Derived from the verified China Mobile edition; only carrier binding changed.
set -e
umask 077
pkg=/var/tmp/bb10-volte
# /var/tmp is cleared at boot on this firmware, so keep backup and state persistent.
data=/var/etc/bb10-volte
backup=$data/easy-backup-v1
state=$data/easy-state-v1
export LD_LIBRARY_PATH=/base/usr/lib:/base/lib:/proc/boot:/base/lib/dll:/base/usr/lib/qt4/lib:/radio/lib:/radio/lib/dll:/radio/usr/lib
action=${1:-Check}
mutating=0
busy=$pkg/easy-operation.lock
owns_lock=0

emit() { print -r -- "BBE:$*"; }
fail() { emit "ERROR:$1"; exit 1; }

check_model() {
    test "$(cat /etc/os.version)" = 10.3.3.3216 || fail OS_UNSUPPORTED
    uname -a | grep -q CLASSICVZW || fail MODEL_UNSUPPORTED
    set -- $(cksum /base/sbin/io-pkt-v6-hc)
    test "$1" = 1240815568 -a "$2" = 945248 || fail STACK_UNSUPPORTED
    # Test effective UID without relying on an optional id/whoami binary.
    test -r /proc/1/as || fail ROOT_REQUIRED
}

idle() {
    cat /pps/services/phone/public/status | grep -q 'phone_state::idle' || fail CALL_ACTIVE
}

ready() {
    sim=$(cat /pps/services/cellular/uicc/card0/status_private)
    print -r -- "$sim" | grep '^uicc_state:' | grep -q '"state":"READY"' || fail SIM_NOT_READY
    print -r -- "$sim" | grep '^imsi_hplmn:' | grep -q '"mcc":"460","mnc":"01"' || fail SIM_UNSUPPORTED
    cat /pps/services/cellular/radioctrl/status_public | grep -q 'network_technology:json:\["lte"\]' || fail LTE_REQUIRED
}

# This firmware reports default_ran in lower case, so compare case-insensitively.
ims_ok() {
    snapshot=$(cat /pps/services/ims/status_public 2>/dev/null) || return 1
    print -r -- "$snapshot" | grep -q 'status::connected' &&
    print -r -- "$snapshot" | grep -iq 'default_ran::lte' &&
    print -r -- "$snapshot" | grep '^deviceConfig:json:' | grep -q '"VoLTE"'
}

ensure_trust() {
    # This firmware only executes images on signed filesystems. pathtrust can
    # trust one file for mmap, or the whole filesystem for execution, until the
    # next reboot; both marks are re-applied by every Enable run.
    chmod 755 "$pkg/volte-berry" 2>/dev/null || :
    /proc/boot/pathtrust "!$pkg/volte-berry" > /dev/null 2>&1 || :
    /proc/boot/pathtrust "!$pkg/devnp-volte-swcrypto.so" > /dev/null 2>&1 || :
    if "$pkg/volte-berry" --self-test > /dev/null 2>&1; then return 0; fi
    /proc/boot/pathtrust "$pkg/volte-berry" > /dev/null 2>&1 || :
    if "$pkg/volte-berry" --self-test > /dev/null 2>&1; then
        emit PATHTRUST_FS
        return 0
    fi
    return 1
}
ims_running() { pidin ar | grep -q '^ *[0-9][0-9]* /radio/bin/ims_rrm '; }
berry_running() { pidin ar | grep -q '^ *[0-9][0-9]* /var/tmp/bb10-volte/volte-berry *$'; }
stop_ims() {
    if ims_running; then
        slay -f -sTERM ims_rrm || :
        sleep 2
        if ims_running; then fail IMS_STOP_FAILED; fi
    fi
}
start_ims() { on -d /radio/bin/ims_rrm -U 453:31,80,387,427,521,1001 > "$pkg/ims-start.log" 2>&1; }
stop_berry() {
    if berry_running; then
        slay -f -sTERM volte-berry || :
        sleep 1
        if berry_running; then fail BERRY_STOP_FAILED; fi
    fi
}
# This firmware only executes signed images outside writable storage, so the
# indicator tracker and the crypto provider are best effort, not fatal.
try_berry() {
    chmod 755 "$pkg/volte-berry"
    if ! "$pkg/volte-berry" --self-test > /dev/null 2>&1; then
        emit BERRY_UNAVAILABLE
        return 1
    fi
    if ! berry_running; then on -d "$pkg/volte-berry" > "$pkg/berry.log" 2>&1; sleep 1; fi
    if berry_running; then return 0; fi
    emit BERRY_UNAVAILABLE
    return 1
}

make_backup() {
    if [ -f "$backup/complete" ]; then emit BACKUP_EXISTS; return; fi
    test ! -e "$backup" || fail BACKUP_INCOMPLETE
    # A new staging directory is deliberately retained if backup fails.
    mkdir -p "$data"
mkdir "$backup"
    cat > "$backup/targets" <<'FILES'
ims/services/carrier_config/ims/ims
ims/services/carrier_config/radio_common/cellular_protocol_configuration
ims_defaults/services/carrier_config/radio_common/cellular_protocol_configuration
omadm/services/carrier_config/radio_common/cellular_protocol_configuration
test/services/carrier_config/radio_common/cellular_protocol_configuration
test/services/carrier_config/radio_qct/ims
FILES
    : > "$backup/present"
    : > "$backup/missing"
    while IFS= read -r relative; do
        path=/var/dca/sources/$relative
        if [ -f "$path" ] && [ ! -L "$path" ]; then
            echo "$relative" >> "$backup/present"
        elif [ -e "$path" ] || [ -L "$path" ]; then
            fail CONFIG_NOT_REGULAR
        else
            echo "$relative" >> "$backup/missing"
        fi
    done < "$backup/targets"
    tar -cf "$backup/dca.tar" -C /var/dca/sources -T "$backup/present"
    cat /pps/services/cds/cnice/status_persistent | sed -n 's/^cdsc_xml:://p' > "$backup/cdsc_xml"
    lines=$(wc -l < "$backup/cdsc_xml")
    test "$lines" -eq 1 || fail XML_BACKUP_FAILED
    oldxml=$(cat "$backup/cdsc_xml")
    if [ -n "$oldxml" ]; then
        test -f "$oldxml" || fail XML_BACKUP_FAILED
        cp -p "$oldxml" "$backup/carrier-before.xml"
    fi
    if ims_running; then touch "$backup/ims-was-running"; fi
    if berry_running; then touch "$backup/berry-was-running"; fi
    echo 'BB10-VoLTE-Easy-backup-v1' > "$backup/complete"
    emit BACKUP_CREATED
}

restore_config() {
    test -f "$backup/complete" || return 1
    stop_berry
    # The state marker can be lost across a reboot, so key off the backup itself.
    stop_ims
    tar -xf "$backup/dca.tar" -C /var/dca/sources
    # These paths are fixed by our own target list, never by user input.
    while IFS= read -r relative; do
        case "$relative" in
            ims/services/carrier_config/ims/ims|ims/services/carrier_config/radio_common/cellular_protocol_configuration|ims_defaults/services/carrier_config/radio_common/cellular_protocol_configuration|omadm/services/carrier_config/radio_common/cellular_protocol_configuration|test/services/carrier_config/radio_common/cellular_protocol_configuration|test/services/carrier_config/radio_qct/ims)
                rm -f "/var/dca/sources/$relative" ;;
            *) return 1 ;;
        esac
    done < "$backup/missing"
    oldxml=$(cat "$backup/cdsc_xml")
    # Restore a saved copy if the old override file has since gone missing.
    if [ -n "$oldxml" ] && [ ! -f "$oldxml" ]; then
        oldxml=$pkg/carrier-restored.xml
        cp -p "$backup/carrier-before.xml" "$oldxml"
        chmod 644 "$oldxml"
    fi
    print -r -- "cdsc_xml::$oldxml" >> /pps/services/cds/cnice/status_persistent
    dca -s -a /pps > "$pkg/dca-restore.log" 2>&1 || return 1
    if [ -f "$state/provider-owned" ]; then
        mount -T io-pkt -o disable "$pkg/devnp-volte-swcrypto.so" || return 1
    fi
    if [ -f "$backup/ims-was-running" ]; then start_ims; fi
    rm -f "$state/config-changed" "$state/provider-owned"
    if [ -f "$backup/berry-was-running" ]; then try_berry || :; fi
}

finish() {
    result=$?
    trap - 0 INT TERM HUP
    if [ "$mutating" = 1 ] && [ "$result" != 0 ]; then
        emit ROLLBACK_STARTED
        set +e
        # Run with errexit in a subshell so any failed restore command stops it.
        (set -e; restore_config)
        if [ "$?" = 0 ]; then emit ROLLBACK_OK; else emit ERROR:ROLLBACK_FAILED; fi
    fi
    if [ "$owns_lock" = 1 ]; then rm -R -f "$busy"; fi
    exit "$result"
}

check_model
case "$action" in
Check|Probe)
    emit COMPATIBLE
    if [ "$action" = Check ]; then ready; emit SIM_LTE_OK; fi
    if ims_ok; then emit CONNECTED; else emit NOT_CONNECTED; fi
    if berry_running; then emit BERRY_RUNNING; else emit BERRY_STOPPED; fi
    if [ -f "$backup/complete" ]; then emit BACKUP_EXISTS; fi
    exit 0 ;;
Enable|Restore|BerryOff) ;;
*) fail ACTION_INVALID ;;
esac
idle
if ! mkdir "$busy" 2>/dev/null; then
    sleep 1
    previous_pid=$(cat "$busy/pid" 2>/dev/null || echo 0)
    case "$previous_pid" in ''|*[!0-9]*) fail OPERATION_BUSY ;; esac
    if [ "$previous_pid" != 0 ] && kill -0 "$previous_pid" 2>/dev/null; then fail OPERATION_BUSY; fi
    # Recover only our fixed lock directory left by a terminated operation/reboot.
    rm -R -f "$busy"
    mkdir "$busy" || fail OPERATION_BUSY
fi
owns_lock=1
echo $$ > "$busy/pid"
trap finish 0
trap 'exit 1' INT TERM HUP
mkdir -p "$data" "$state"

case "$action" in
Enable)
    ready
    make_backup
    if ! ensure_trust; then fail PATHTRUST_FAILED; fi
    if ims_ok && [ "${2:-}" != Refresh ]; then
        try_berry || :
        emit ALREADY_CONNECTED
        exit 0
    fi
    emit APPLYING
    mutating=1
    touch "$state/config-changed"
    provider_present=0
    if mount -T io-pkt -o status "$pkg/devnp-volte-swcrypto.so" > /dev/null 2>&1; then
        provider_present=1
    fi
    if mount -T io-pkt -o enable "$pkg/devnp-volte-swcrypto.so" > "$pkg/provider.log" 2>&1; then
        [ "$provider_present" = 1 ] || touch "$state/provider-owned"
    else
        emit PROVIDER_SKIPPED
    fi
    while IFS= read -r relative; do
        mkdir -p "/var/dca/sources/${relative%/*}"
    done < "$backup/targets"
    cat > /var/dca/sources/ims/services/carrier_config/ims/ims <<'CFG'
@ims
IMS_services:json:[{"service":"voice","feature_tag":"urn:urn-7:3gpp-service.ims.icsi.mmtel","network":["LTE"]}]
Mobility_Management_IMS_Voice_Termination:n:1
IMS_profilesV2:json:["IR92"]
supported_networks:json:["LTE"]
PCSCF_discoveryV2:json:["PCO"]
SDK_Config::3GPP
IMS_always_on:b:true
CFG
    for src in ims ims_defaults omadm test; do
        cat > "/var/dca/sources/$src/services/carrier_config/radio_common/cellular_protocol_configuration" <<'CFG'
@cellular_protocol_configuration
voice_domain_preference_EUTRAN:n:3
ue_usage_setting::voice_centric
wcdma_to_lte_ps_ho_support:b:false
CFG
    done
    cat > /var/dca/sources/test/services/carrier_config/radio_qct/ims <<'CFG'
@ims
IMS_platform::common
CFG
    dca -s -a /pps > "$pkg/dca-enable.log" 2>&1
    chmod 644 "$pkg/carrier-36-volte.xml"
    echo "cdsc_xml::$pkg/carrier-36-volte.xml" >> /pps/services/cds/cnice/status_persistent
    stop_ims
    start_ims
    try_berry || :
    i=0
    while [ "$i" -lt 30 ]; do
        if ims_ok; then mutating=0; emit CONNECTED; exit 0; fi
        if [ $((i % 5)) = 0 ]; then emit "WAITING:$((i * 2))"; fi
        sleep 2
        i=$((i + 1))
    done
    fail REGISTER_TIMEOUT
    ;;
Restore)
    test -f "$backup/complete" || fail NO_BACKUP
    restore_config
    emit RESTORED
    ;;
BerryOff)
    stop_berry
    emit BERRY_DISABLED
    ;;
esac
