# Source export

This repository is a curated snapshot of the PaperDesk source tree, prepared on 2026-10-22.
It includes the current application source, website, installers, tests and documentation.
It intentionally excludes local build outputs, release archives, development workspaces,
service data, SSH keys, credentials, private operations reports and host-specific state.

The canonical working tree is maintained separately; this initial GitHub import does
not rewrite or commit the original working tree and may contain changes newer than
its last committed revision. Firmware recovery guidance was added to the website
on 2026-10-22. Device-side firmware modifications and XOVI are third-party projects.

## Installer candidate update, 2026-10-29

The manual Windows/Linux installer, matching PaperCare resources and product manifest
were integrated from the authoritative working tree without committing or resetting it.
The existing GitHub-only source and recovery guidance are preserved.
Build artifacts are supplied separately as a draft candidate release, not in Git.
See docs/INSTALLER-BUILD-2026-10-29.md for validation and physical USB test limits.
The Windows executable remains unsigned because no Authenticode certificate is available.
