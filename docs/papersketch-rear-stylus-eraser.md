# Rear stylus eraser and removal of the progressive prototype

The active Paper Sketch build uses the synchronous material renderer. The
half-resolution preview, background material worker and Live preview switch
are absent. The earlier zero-pressure onset fix and 16 ms publication remain.

The rear end of a supported stylus temporarily uses the normal hard eraser,
with the eraser tool's default size and full strength. It does not alter the
selected drawing tool, brush size, strength or chosen kneaded-eraser setting.
Those settings continue to apply when the normal nib is used again. As with
the existing graphite erasers, permanent Rapidograph ink is unaffected.

Qt's PointerDevice.Eraser hint is accepted. For tablet-synthesized mouse events,
the native backend checks the current Wacom BTN_TOOL_RUBBER/BTN_TOOL_PEN keys
on contact, without waiting for the background reader. Raw samples also retain
the tool flag, so a short released contact can still be matched by position.
Proximity state is cleared when the reader pauses.

Validation: 18 native groups and 54 QML checks pass (2 existing skips). The
native test verifies raw rear/normal sample matching and absence of the
experimental renderer. The QML test verifies temporary hard erasing without
changing drawing settings. An isolated tablet evdev test performs a stationary
rear contact, a rear drag, and a normal pen stroke afterwards. Both erase probes
lighten the seeded graphite/charcoal; the normal nib resumes the selected pencil.
Saved artwork is preserved. Raw device reports are retained locally.

Qt API references: [PointerDevice.pointerType](https://doc.qt.io/qt-6/qml-qtquick-pointerdevice.html)
and [handlerPoint.device](https://doc.qt.io/qt-6/qml-qtquick-handlerpoint.html).

## Rear eraser contact strength (4.2.5)

A positive rear contact uses the ordinary hard eraser at full contact pressure, independently of the drawing-nib calibration. Zero pressure remains a hover and does not erase; a stationary rise starts the first erasing dab. Flipping back clears this override. A manually selected eraser and all drawing tools retain their pressure response. Permanent Rapidograph ink remains unaffected.
