#!/bin/sh
# BB10 VoLTE Unicom for BlackBerry Passport (WINDERMERE4ROW) on BB10 10.3.3.3216.
# Only carrier/IMS configuration is changed; no modem NV and no BBM service.
set -e
umask 077
addon=/var/addons/bb10-volte-unicom
pkg=$addon/data
data=/var/etc/bb10-volte-unicom
backup=$data/easy-backup-v1
state=$data/easy-state-v1
run=/var/tmp/bb10-volte-unicom
ims_xml=/var/ims/carrier/imsconfig_036.xml
ir92=/var/dca/sources/ims/services/carrier_config/ims/ir92
export LD_LIBRARY_PATH=/base/usr/lib:/base/lib:/proc/boot:/base/lib/dll:/base/usr/lib/qt4/lib:/radio/lib:/radio/lib/dll:/radio/usr/lib
action=${1:-Check}
mutating=0
busy=$run/operation.lock
owns_lock=0

emit() { print -r -- "BBE:$*"; }
fail() { emit "ERROR:$1"; exit 1; }

check_model() {
    test "$(cat /etc/os.version)" = 10.3.3.3216 || fail OS_UNSUPPORTED
    cat /pps/services/hw_info/inventory | grep -q '^Board_Type::WINDERMERE4ROW$' || fail MODEL_UNSUPPORTED
    set -- $(cksum /base/sbin/io-pkt-v6-hc)
    test "$1" = 1240815568 -a "$2" = 945248 || fail STACK_UNSUPPORTED
    # Effective-UID test that does not depend on an optional id/whoami binary.
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
    cat /pps/services/cds/cnice/status_persistent | grep -q '^data_service_mode::ON' || fail DATA_OFF
}

ims_ok() {
    snapshot=$(cat /pps/services/ims/status_public 2>/dev/null) || return 1
    print -r -- "$snapshot" | grep -q 'status::connected' &&
    print -r -- "$snapshot" | grep -iq 'default_ran::lte' &&
    print -r -- "$snapshot" | grep '^deviceConfig:json:' | grep -q '"VoLTE"'
}

# Incoming calls need both the carrier user setting and the IR92 compatibility
# setting. Without the first one the network did not route MT calls to this
# Passport at all; without the second one it cancelled the call right after
# the 180 Ringing on this Unicom/ZTE network.
incoming_ready() {
    cat /pps/services/ims/status_public 2>/dev/null | grep -q 'allowVoLteProvisioning:n:1' &&
    cat /pps/services/carrier_config/ims/ir92 2>/dev/null | grep -q '^UsePreconditions:n:0'
}

ims_running() { pidin ar | grep -q '^ *[0-9][0-9]* /radio/bin/ims_rrm '; }
berry_running() { pidin ar | grep -q "^ *[0-9][0-9]* $pkg/volte-berry *\$"; }

ensure_addon_metadata() {
    # This firmware only executes binaries from addons that carry a MANIFEST,
    # perms and trusted list. The marks are applied at boot; a freshly
    # installed addon therefore needs one reboot before its binaries run.
    mkdir -p "$addon/init" "$pkg"
    cat > "$addon/MANIFEST" <<'EOF'
Package-Id: bb10-volte-unicom
Package-Name: BB10 Passport China Unicom VoLTE
Package-Version: 1.1
EOF
    cat > "$pkg/perms" <<'EOF'
volte-berry:0:0:0755
devnp-volte-swcrypto.so:0:0:0755
carrier-36-volte.xml:0:0:0644
EOF
    cat > "$pkg/trusted" <<'EOF'
/var/addons/bb10-volte-unicom/data/volte-berry
/var/addons/bb10-volte-unicom/data/devnp-volte-swcrypto.so
EOF
}

trust_ok() { "$pkg/volte-berry" --self-test > /dev/null 2>&1; }

provider_enable() {
    # Loads BB10's built-in software crypto provider. Required for the IMS
    # IPsec bearer on this firmware. The same file path must be used for every
    # mount call because the provider state lives in the loaded image.
    mount -T io-pkt -o enable "$pkg/devnp-volte-swcrypto.so" > "$run/provider.log" 2>&1 || fail PROVIDER_FAILED
}

stop_ims() {
    if ims_running; then
        slay -f -sTERM ims_rrm || :
        # IPsec/UAS port 50001 needs to be released before the next engine;
        # a short wait causes 403 Forbidden on re-registration.
        i=0
        while [ "$i" -lt 15 ]; do
            if ! ims_running; then sleep 2; return 0; fi
            sleep 1
            i=$((i + 1))
        done
        fail IMS_STOP_FAILED
    fi
}
start_ims() { on -d /radio/bin/ims_rrm -U 453:31,80,387,427,521,1001 > "$run/ims-start.log" 2>&1; }

stop_berry() {
    if berry_running; then
        slay -f -sTERM volte-berry || :
        i=0
        while [ "$i" -lt 5 ]; do
            if ! berry_running; then return 0; fi
            sleep 1
            i=$((i + 1))
        done
        fail BERRY_STOP_FAILED
    fi
}
start_berry() {
    chmod 755 "$pkg/volte-berry" 2>/dev/null || return 1
    "$pkg/volte-berry" --self-test > /dev/null 2>&1 || { emit BERRY_UNAVAILABLE; return 1; }
    # The indicator binary keeps its lock in this fixed runtime directory.
    mkdir -p /var/tmp/bb10-volte 2>/dev/null || :
    if ! berry_running; then
        on -d "$pkg/volte-berry" > "$run/berry.log" 2>&1
        sleep 1
    fi
    berry_running || { emit BERRY_UNAVAILABLE; return 1; }
    return 0
}

enable_volte_provisioning() {
    # The IMS engine reads this user setting at start. Editing in place keeps
    # the ims:radio ownership and 0600 mode intact.
    if [ -f "$ims_xml" ] && grep -q '<AllowVoLteProvisioning>disabled</AllowVoLteProvisioning>' "$ims_xml"; then
        sed 's|<AllowVoLteProvisioning>disabled</AllowVoLteProvisioning>|<AllowVoLteProvisioning>enabled</AllowVoLteProvisioning>|' "$ims_xml" > "$run/imsconfig.new"
        cat "$run/imsconfig.new" > "$ims_xml"
    fi
}

ensure_incoming_compat() {
    mkdir -p /var/dca/sources/ims/services/carrier_config/ims
    cat > "$ir92" <<'CFG'
@ir92
UsePreconditions:n:0
SMS_Format::3GPP
amr_modeset_list::7
amrwb_modeset_list::2
CFG
}

ensure_backup_extras() {
    if [ ! -f "$backup/ir92.before" ] && [ ! -f "$backup/ir92.missing" ]; then
        if [ -f "$data/ir92.before" ]; then
            cp -p "$data/ir92.before" "$backup/ir92.before"
        elif [ -f "$ir92" ]; then
            cp -p "$ir92" "$backup/ir92.before"
        else
            : > "$backup/ir92.missing"
        fi
    fi
    if [ ! -f "$backup/imsconfig_036.xml" ] && [ ! -f "$backup/imsconfig_036.missing" ]; then
        if [ -f "$data/imsconfig_036.before" ]; then
            cp -p "$data/imsconfig_036.before" "$backup/imsconfig_036.xml"
        elif [ -f "$ims_xml" ]; then
            cp -p "$ims_xml" "$backup/imsconfig_036.xml"
        else
            : > "$backup/imsconfig_036.missing"
        fi
    fi
}

make_backup() {
    if [ -f "$backup/complete" ]; then
        ensure_backup_extras
        emit BACKUP_EXISTS
        return 0
    fi
    test ! -e "$backup" || fail BACKUP_INCOMPLETE
    mkdir -p "$state"
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
    cp /pps/services/escreens/config "$backup/escreens" 2>/dev/null || :
    if ims_running; then touch "$backup/ims-was-running"; fi
    if berry_running; then touch "$backup/berry-was-running"; fi
    ensure_backup_extras
    echo 'BB10-VoLTE-Unicom-Passport-backup-v1' > "$backup/complete"
    emit BACKUP_CREATED
}

restore_config() {
    test -f "$backup/complete" || return 1
    stop_berry
    stop_ims
    tar -xf "$backup/dca.tar" -C /var/dca/sources
    # Paths are fixed by our own target list, never by user input.
    while IFS= read -r relative; do
        case "$relative" in
            ims/services/carrier_config/ims/ims|ims/services/carrier_config/radio_common/cellular_protocol_configuration|ims_defaults/services/carrier_config/radio_common/cellular_protocol_configuration|omadm/services/carrier_config/radio_common/cellular_protocol_configuration|test/services/carrier_config/radio_common/cellular_protocol_configuration|test/services/carrier_config/radio_qct/ims)
                rm -f "/var/dca/sources/$relative" ;;
            *) return 1 ;;
        esac
    done < "$backup/missing"
    if [ -f "$backup/ir92.before" ]; then
        cp -p "$backup/ir92.before" "$ir92"
    elif [ -f "$backup/ir92.missing" ]; then
        rm -f "$ir92"
    fi
    if [ -f "$backup/imsconfig_036.xml" ]; then
        cp -p "$backup/imsconfig_036.xml" "$ims_xml"
        chown ims:radio "$ims_xml" 2>/dev/null || :
        chmod 600 "$ims_xml" 2>/dev/null || :
    elif [ -f "$backup/imsconfig_036.missing" ]; then
        rm -f "$ims_xml"
    fi
    oldxml=$(cat "$backup/cdsc_xml")
    # If the original override file has since disappeared, restore the saved
    # copy so the old path still points at valid content.
    if [ -n "$oldxml" ] && [ ! -f "$oldxml" ] && [ -f "$backup/carrier-before.xml" ]; then
        oldxml=$data/carrier-restored.xml
        cp -p "$backup/carrier-before.xml" "$oldxml"
        chmod 644 "$oldxml"
    fi
    print -r -- "cdsc_xml::$oldxml" >> /pps/services/cds/cnice/status_persistent
    dca -s -a /pps > "$run/dca-restore.log" 2>&1 || return 1
    # Put back the original engineering-screen voice-domain value (this phone
    # ships with 2 = no override). The crypto provider is deliberately left
    # loaded: unloading it on this firmware can restart io-pkt, and it is a
    # runtime capability cleared by the next reboot anyway.
    orig=$(sed -n 's/^voice_domain_preference_EUTRAN_override:://p' "$backup/escreens" 2>/dev/null | sed -n '$p')
    case "$orig" in ''|*[!0-9]*) orig=2 ;; esac
    print -r -- "voice_domain_preference_EUTRAN_override::$orig" >> /pps/services/escreens/config 2>/dev/null || :
    if [ -f "$backup/ims-was-running" ]; then start_ims; fi
    if [ -f "$backup/berry-was-running" ]; then start_berry || :; fi
    rm -f "$state/config-changed"
}

wait_connected() {
    i=0
    while [ "$i" -lt 30 ]; do
        if ims_ok; then return 0; fi
        if [ $((i % 5)) = 0 ]; then emit "WAITING:$((i * 2))"; fi
        sleep 2
        i=$((i + 1))
    done
    return 1
}

finish() {
    result=$?
    trap - 0 INT TERM HUP
    if [ "$mutating" = 1 ] && [ "$result" != 0 ]; then
        emit ROLLBACK_STARTED
        set +e
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
    if incoming_ready; then emit INCOMING_READY; else emit INCOMING_NOT_READY; fi
    exit 0 ;;
Enable|Restore|BerryOff) ;;
*) fail ACTION_INVALID ;;
esac
idle
mkdir -p "$run" "$state" 2>/dev/null || :
if ! mkdir "$busy" 2>/dev/null; then
    sleep 1
    previous_pid=$(cat "$busy/pid" 2>/dev/null || echo 0)
    case "$previous_pid" in ''|*[!0-9]*) fail OPERATION_BUSY ;; esac
    if [ "$previous_pid" != 0 ] && kill -0 "$previous_pid" 2>/dev/null; then fail OPERATION_BUSY; fi
    # Recover only our fixed lock directory left by a terminated run or reboot.
    rm -R -f "$busy"
    mkdir "$busy" || fail OPERATION_BUSY
fi
owns_lock=1
echo $$ > "$busy/pid"
trap finish 0
trap 'exit 1' INT TERM HUP

case "$action" in
Enable)
    ready
    make_backup
    if ! trust_ok; then
        ensure_addon_metadata
        fail REBOOT_REQUIRED
    fi
    provider_enable
    if ims_ok && incoming_ready && [ "${2:-}" != Refresh ]; then
        start_berry || :
        emit ALREADY_CONNECTED
        exit 0
    fi
    emit APPLYING
    mutating=1
    touch "$state/config-changed"
    ensure_incoming_compat
    enable_volte_provisioning
    mkdir -p /var/dca/sources/ims/services/carrier_config/ims
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
        mkdir -p "/var/dca/sources/$src/services/carrier_config/radio_common"
        cat > "/var/dca/sources/$src/services/carrier_config/radio_common/cellular_protocol_configuration" <<'CFG'
@cellular_protocol_configuration
voice_domain_preference_EUTRAN:n:3
ue_usage_setting::voice_centric
wcdma_to_lte_ps_ho_support:b:false
CFG
    done
    mkdir -p /var/dca/sources/test/services/carrier_config/radio_qct
    cat > /var/dca/sources/test/services/carrier_config/radio_qct/ims <<'CFG'
@ims
IMS_platform::common
CFG
    dca -s -a /pps > "$run/dca-enable.log" 2>&1 || fail DCA_FAILED
    chmod 644 "$pkg/carrier-36-volte.xml"
    print -r -- "cdsc_xml::$pkg/carrier-36-volte.xml" >> /pps/services/cds/cnice/status_persistent
    # 5 = IMS PS Voice Only. Unicom has no usable 2G/3G CS domain here, so the
    # phone must not hand calls to CS fallback.
    print -r -- "voice_domain_preference_EUTRAN_override::5" >> /pps/services/escreens/config 2>/dev/null || :
    stop_ims
    start_ims
    start_berry || :
    if ! wait_connected; then fail REGISTER_TIMEOUT; fi
    if ! incoming_ready; then
        # First run on a fresh phone: the engine creates imsconfig_036.xml
        # during the first start, so enable the user setting and restart once.
        emit INCOMING_RETRY
        stop_ims
        enable_volte_provisioning
        start_ims
        wait_connected || fail REGISTER_TIMEOUT
    fi
    incoming_ready || fail INCOMING_FAILED
    mutating=0
    emit CONNECTED
    exit 0
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
