# Earlier parallel charcoal rows — prepared candidate, not UAT

Base 802925a, installed rowspan raster29d4827. One material change: lower
parallel row dispatch footprint area threshold from 200 to100; retain
minimum16-row span, per-dab synchronization, ordered dabs and disjoint rows.
Pressure, pigment, points, sampling and publication remain unchanged.

Selected from ten independent ARM CPU probes. Six opposite-order timing
pairs show lower charcoal trace cost, but these are not GUI/panel latency
measurements. Do not describe this as a demonstrated responsiveness fix.

Built raster SHA256 e5cec0157c2c0b58bed9c099a433bf5df919e92654060233413052c1a518f314.
Material SHA256 1b5ae45231f5ea8b3c2b978c71af0ec62715b646d0c58a2197c0c63ea642a756.
Installer explicitly accepts frozen `--baseline rowspan-20261121` only with
matching actual hashes; a new fault-injected test covers that baseline.

Full host regression suite passed: 33 C++ and2 C executables. Seven installer
fault-injection tests and six report-validation tests passed. Product checksum
verification and git diff whitespace checks passed. ARM exact-state checks
passed in three independent executions of the standalone probe.

Installation and guarded GUI measurement require confirmation that current
scratch work can be discarded or has been saved. Nothing in this candidate
authorizes deletion of saved artwork or a production release. It has NOT
been installed or accepted into UAT in this session.
