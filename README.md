# Soulshard Lookup

WoW TBC Anniversary addon for interface **20506**. This repository contains the installable addon source and its artwork and catalogs.

## Install

Download `SoulshardLookup.zip` from the [latest release](https://github.com/Spatovaliyski/Soulshard.io-lookup/releases/latest). Exit WoW, back up the current addon folder and account settings, then replace the complete `SoulshardLookup` folder under `Interface/AddOns`. Do not merge releases or datasets.

Published releases contain matching addon code and a saved-profile snapshot from [Soulshard](https://soulshard.io). Daily data builds retain each character's actual collection date. Nearby equipment and talents use live inspection. Use `/sl` or `/lookup` for profiles and `/sl settings` for the Whisper Collector.

See [installation and rollback](SoulshardLookup/INSTALL.txt) and the bundled [artwork and catalog notices](SoulshardLookup/NOTICE.txt).

## Addon development

Edit `SoulshardLookup/` and merge release-ready changes into `main`. The source checkout contains empty data stubs; use a complete published release for saved character data.

For a code release, keep the numeric version in `Core.lua` and `SoulshardLookup.toc` consistent, then push the matching `vX.Y.Z` tag, such as `v0.5.0`. The small tag workflow requests a release from the private publishing service. Daily packages use current `main` and new saved data. Packaging, tests and previews are maintained with the private website backend.

Tag requests stay disabled until the repository variable `RELEASES_ENABLED` is `true` and the `BUILDER_DISPATCH_TOKEN` Actions secret is configured. That credential must have Actions write access only to the publishing repository. Daily GitHub packages can run before CurseForge setup; CurseForge uploads are enabled separately in the private publishing service.

Native WoW compatibility and representative dataset load checks remain part of release validation. Automated checks do not certify in-game behavior.
