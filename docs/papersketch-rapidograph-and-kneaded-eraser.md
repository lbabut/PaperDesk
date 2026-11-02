# Rapidograph and kneaded eraser

Rapidograph is tool 8; existing tool numbers remain unchanged. It draws a black,
antialiased line of constant selected width, independent of positive pen pressure,
tilt, paper tooth and tip wear. Ink is a separate RAM layer and is unaffected by
finger smudging or either graphite eraser. Clear/delete page removes it.
Material cache v3 stores ink; pages without ink still use v2. Existing v1/v2 pages
remain readable. PDF export includes ink.

Kneaded eraser now responds to increasing pen pressure after initial contact and
lifts pigment along its path. Its soft footprint retains 70% of selected width at
very light pressure. Each pixel has a per-contact removal cap: up to 55% of loose
pigment and 12% of fixed pigment at full pressure. More input events at the same
pressure do not keep abrading the paper. Lift and dab again to lift another layer.
This cap is transient, held only in RAM, and is never serialized or used as undo.

Regression coverage includes zero-pressure starts, stationary light-to-firm
pressure, moving contact, repeated samples and fresh dabs, cache compatibility,
permanent ink, export pixels and bounded footprints. The real-device realism
probe additionally selects Kneaded through the UI and injects a stationary pen
pressure ramp and a moving stroke through /dev/input/event1. Device validation passed on reMarkable 2 through injected evdev input: stationary
pressure increased from 0.125 to 0.88 and pixel gray rose from 7 to 26; the moving
eraser lifted a separate probe from 176 to 196. The diagnostic pressure-ramp
pattern now varies pressure explicitly and initializes both pen axes on fresh
Qt readers, including repeat runs. This is software-input validation, not an
optical panel measurement or a manual stylus trial.

The development installer writes the launch configuration as real INI lines,
so --launch opens Paper Sketch after restarting xochitl.
