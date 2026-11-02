# Rear eraser contact strength

The first rear-stylus implementation selected the correct eraser and tool strength but still passed the rear sensor through the drawing-nib pressure response. That attenuated its physical contact in the material engine. Earlier injected tests used 55 percent pressure, so they did not cover a very light rear touch.

The renderer now treats positive rear contact as full contact for the ordinary hard eraser. It retains zero-pressure hover/onset handling and resets the override when the stroke ends, the tool is released or the page resets. This does not change the material equations, manually selected erasers, drawing-nib calibration, finger blending or permanent ink.

Behavioral native tests compare low and firm rear contact on the same seeded material, verify a stationary zero-to-positive onset and the return of normal pressure sensitivity. The device probe now includes a separate hover frame and a 1.5 percent rear pressure, followed by normal-nib resumption. Raw device logs remain local.

Validation: 18 native test groups passed; QML 54 passed, 0 failed, 2 skipped. On reMarkable 2, the 1.5 percent rear-contact probe passed for a stationary dab and drag, then the normal nib resumed with its selected settings. In the seeded probe the tap pixel changed from 12 to 59 and the drag pixel from 141 to 251 (0 black, 255 white); these are raster values, not optical measurements. Saved pages were preserved.

Manual validation: the owner confirmed that light contact and rear erasing now have appropriate strength on the physical stylus, after the diagnostic-only build had been removed.
