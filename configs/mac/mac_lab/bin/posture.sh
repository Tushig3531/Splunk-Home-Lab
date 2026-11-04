#!/bin/bash
echo "filevault=\"$(fdesetup status)\" firewall=\"$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate)\" gatekeeper=\"$(spctl --status)\" sip=\"$(csrutil status)\""
