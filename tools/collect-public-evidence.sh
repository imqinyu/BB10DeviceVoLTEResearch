#!/bin/sh
# Read-only, allowlist-based evidence collection. No service or trust changes.
set -e
echo BB10_PUBLIC_EVIDENCE_BEGIN
echo '[hardware]'
uname -m
cat /pps/services/hw_info/inventory 2>/dev/null | grep -E '^(Board_Type|Model_Number|Model_Name):' || :
echo '[os]'
cat /etc/os.version
echo '[firmware-checksums]'
cksum /base/sbin/io-pkt-v6-hc /radio/bin/ims_rrm
echo '[ims-public-selected]'
cat /pps/services/ims/status_public 2>/dev/null | grep -E '^(\[n\])?(status|default_ran|default_sys|deviceConfig|profiles|SMS_Format|allowVoLteProvisioning|WiFiCalling_enabled|roaming):' || :
echo '[radio-public-selected]'
cat /pps/services/cellular/radioctrl/status_public 2>/dev/null | grep -E '^(\[n\])?(band_capability|active_bands|network_technology|power_status|cell_search_status):' || :
echo '[sim-selected-not-identity]'
# Read only these two non-unique attributes; never emit IMSI or ICCID.
cat /pps/services/cellular/uicc/card0/status_private 2>/dev/null | grep -E '^(\[n\])?(imsi_hplmn|uicc_state):' || :
echo '[data-service-selected]'
cat /pps/services/cds/cnice/status_persistent 2>/dev/null | grep -E '^(\[n\])?data_service_mode:' || :
echo '[ir92-selected]'
cat /pps/services/carrier_config/ims/ir92 2>/dev/null | grep -E '^(\[n\])?(UsePreconditions|SMS_Format|amr_modeset_list|amrwb_modeset_list):' || :
echo '[escreens-selected]'
cat /pps/services/escreens/config 2>/dev/null | grep -E '^(\[n\])?voice_domain_preference_EUTRAN_override:' || :
echo '[navigator-dots]'
cat /pps/system/navigator/status/bb_service 2>/dev/null | grep -E '^(\[n\])?dat:' || :
echo '[boot-software-crypto-line]'
cat /base/scripts/net.sh 2>/dev/null | grep 'disable_swcrypto=' || :
echo BB10_PUBLIC_EVIDENCE_END
