# Splunk Home Lab

A small home lab that uses Splunk as a SIEM to collect, search and alert on security events from a Mac, a Raspberry Pi and an iPhone. I built it to practice the day to day work of a SOC analyst: getting data in, making it searchable, writing detections, testing them, and fixing things when they break.

This is a learning project, not a production setup. Notes on its limits are at the end.

## Architecture

```
                 +-----------------------------+
                 |  MacBook Air (M2)           |
                 |  Splunk Enterprise (server) |
                 |  Universal Forwarder        |
                 +--------------+--------------+
                                ^
                                | logs over TCP 9997
                                |
                 +--------------+--------------+
                 |  Raspberry Pi 4             |
                 |  Universal Forwarder        |
                 |  auditd, UFW, Pi-hole       |
                 +--------------+--------------+
                                ^
                                | DNS lookups
                                |
                 +--------------+--------------+
                 |  iPhone                     |
                 |  (DNS set to the Pi)        |
                 +-----------------------------+
```

| Device | Role | Software |
|---|---|---|
| MacBook Air M2 | Splunk server and monitored endpoint | Splunk Enterprise (macOS build under Rosetta), Universal Forwarder |
| Raspberry Pi 4 | Monitored Linux server, firewall, DNS filter | Raspberry Pi OS 64 bit, Universal Forwarder (ARM64), Splunk Add-on for Unix and Linux, auditd, UFW, Pi-hole |
| iPhone | Monitored mobile device | No agent. Visible through Pi-hole DNS logs |

Splunk Enterprise does not support ARM Linux, so the Pi runs only the forwarder and the Mac hosts the server.

## Data Sources

| Index | Source | Sourcetype | What it shows |
|---|---|---|---|
| pi_linux | /var/log/auth.log | linux_secure | SSH logins, sudo, account changes |
| pi_linux | /var/log/syslog | syslog | General system events |
| pi_linux | /var/log/audit/audit.log | linux_audit | Commands run by users, changes to sensitive files |
| pi_linux | /var/log/ufw.log | ufw | Connections blocked by the firewall |
| pi_linux | /var/log/dpkg.log | dpkg | Software installed or removed |
| pi_linux | Unix add-on scripts | openPorts, usersWithLoginPrivs, ps, netstat | Open ports, login capable users, processes, connections |
| macos | Unified log (filtered) | macos:unified | sudo, su, sshd, account and group changes, screen sharing, XProtect |
| macos | Custom script | macos:launchitems | LaunchAgents and LaunchDaemons (persistence) |
| macos | Custom script | macos:posture | FileVault, firewall, Gatekeeper and SIP status |
| macos | /var/log/install.log | (default) | Software installed through installers and updates |
| dns | /var/log/pihole/pihole.log | pihole | DNS lookups and blocked domains for every device using the Pi |

Each index is capped at 5 GB and keeps 90 days of data (`configs/server/indexes.conf`).

## Detections

All alerts run on a schedule and write to Triggered Alerts.

| Alert | Logic | MITRE ATT&CK | How I tested it |
|---|---|---|---|
| Wrong SSH Passwords | 5 or more failed passwords from one source in 5 minutes | T1110 Brute Force | Wrong passwords from the Mac with key login disabled for the test |
| New User Created | `useradd` on the Pi or `sysadminctl` on the Mac | T1136 Create Account | Created and deleted a test user on both devices |
| New Root Access Given | User added to the sudo group, sudoers changed, or Mac admin group changed | T1098 Account Manipulation | Added a test user to the sudo group, then removed it |
| New LaunchAgent on Mac | Startup item not seen in the previous 7 days | T1543.001 Launch Agent | Created an empty test plist in ~/Library/LaunchAgents |
| Device Hitting Blocked Domains | 50 or more blocked lookups from one device in an hour | T1071.004 DNS (possible adware or malware) | Repeated lookups of a known ad domain |
| Software Installed on Pi | New "status installed" entry in dpkg.log | T1072 Software Deployment Tools | Installed and removed a small package |
| Software Installed on Mac | New "Installed" entry in install.log | T1072 Software Deployment Tools | Checked against past installs and updates |

The SPL for each alert is in `detections/`.

## Dashboards

| Dashboard | Purpose |
|---|---|
| Lab Status | One page check: are all devices sending data, key counts, failed logins, firewall blocks, sudo use, new startup items, top sites, fired alerts |
| SOC Overview, Authentication, Network and DNS, Endpoint Integrity, Data Health | More detailed views, packaged as a Splunk app in `app/homelab_soc` |

## Hardening Done Along the Way

1. UFW on the Pi with a default deny policy. SSH, DNS and the Pi-hole web page are allowed only from the home network.
2. Multicast and Bonjour traffic dropped by explicit rules so it does not flood the firewall log.
3. Reviewed the Mac startup items baseline and identified remote access and helper software to remove.
4. SSH key login set up from the Mac to the Pi.

## Problems I Ran Into

Most of the learning came from things that did not work the first time.

| Problem | Cause | Fix |
|---|---|---|
| Could not run Splunk Enterprise on the Pi | Not supported on ARM | Moved the server to the Mac, kept the Pi as a forwarder |
| `logger` test messages never reached Splunk | Newer macOS writes to the unified log, not system.log | Streamed selected unified log events to a file with a LaunchAgent and forwarded that file |
| Mac startup items arrived as one large event | Script output had no timestamps, so Splunk merged the lines | Added `LINE_BREAKER` and `SHOULD_LINEMERGE = false` in props.conf |
| Phone had no internet with Pi-hole as DNS | A leftover dnsmasq from an earlier WiFi project was also bound to port 53 | Disabled the old service and restarted Pi-hole |
| Pi-hole was slow | Pi on WiFi with power saving on | Turned off WiFi power saving, moving the Pi to Ethernet |
| No Pi data for a while | The forwarder had stopped running | Restarted it and later wrote an alert for silent forwarders |
| Firewall events missing under the expected sourcetype | File was first added with the wrong sourcetype | Corrected the input and searched by source |
| Port scan tests did not appear in the firewall log | I was testing the wrong IP address | Confirmed the Pi's address from the log itself |

## Limitations

1. The Mac has no EDR, so there is no full record of every process it runs.
2. The Pi only sees traffic sent to the Pi, not the whole network.
3. Running Splunk Enterprise on Apple Silicon through Rosetta is not an officially supported setup. The KV store has known issues there.
4. Single instance: one server does indexing and searching.
5. Thresholds are tuned for a quiet home network and would need adjusting anywhere else.

## Next Steps

1. TLS between the forwarders and the server, and HTTPS for the web interface.
2. Separate analyst and admin roles instead of using the admin account.
3. A threat intel lookup (for example abuse.ch) matched against DNS logs.
4. Short incident reports for each simulated attack: alert, investigation, SPL used, conclusion.

## Repository Layout

```
configs/
  server/        indexes.conf, props.conf
  pi/            inputs.conf, Splunk_TA_nix local/inputs.conf, auditd rules, UFW rules
  mac/           inputs.conf, LaunchAgent plist, launch_items.sh, posture.sh
detections/      one .spl file per alert
dashboards/      lab_status.xml
app/homelab_soc/ dashboards and alerts packaged as a Splunk app
screenshots/     alerts firing, dashboards
```
