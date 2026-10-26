# Soulshard Lookup

WoW TBC Anniversary addon for interface **20506**. This repository contains the
public installable source, artwork, catalogs and complete downloadable releases.

## Install

Download `SoulshardLookup.zip` from the [latest release](https://github.com/Spatovaliyski/Soulshard.io-lookup/releases/latest).
Exit WoW, back up your addon folder and account settings, then replace the complete
`SoulshardLookup` folder under `Interface/AddOns`. Do not mix code or datasets from different releases.

Packages include matching addon code and a saved-profile snapshot from [Soulshard](https://soulshard.io).
Actual profile collection dates remain visible. Nearby equipment and talents use live inspection.
Use `/sl` or `/lookup` for profiles and `/sl settings` for the Whisper Collector.
See [installation and rollback](INSTALL.txt) and [notices](NOTICE.txt).

## Release versions

Official versions use `v1.0.1`. Automatic data updates use the same official addon
code plus the export date, such as `v1.0.1-20261028`. A new official version becomes
the base for later automatic releases. Published packages remain fixed.

This repository is maintained automatically from the private authoring workspace.
Only tagged installable addon snapshots are mirrored here; private website and
build tooling stay private. Source checkouts contain empty data stubs; use a full
published ZIP for saved character data. This repository does not trigger release jobs.
