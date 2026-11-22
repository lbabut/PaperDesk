# Rejected serial-row probe

Based on installed rowspan candidate 802925a; frozen reference updated to
that baseline. Disable parallel row dispatch only to measure synchronization
overhead without changing material arithmetic or point ordering.

Standalone ARM exact-state comparisons pass 8100 cross-tool and 2000 varied
charcoal dabs plus stroke traces. Serial soft-charcoal traces are slower:
second repeat new/old ratios 1.4326, 1.5020 and 1.3510 for tilt 0/.5/.95.
Reject. No module build, installation, GUI test or UAT claimed. Product
binary remains baseline; this branch is not an installable candidate.
