# M1 latency spikes

This folder holds the throwaway prototypes of milestone M1 (see [docs/plan.md](../docs/plan.md)). The code does not follow the coding standard. SwiftLint, `swift format`, and the check scripts skip this folder. Delete the folder after M1.

`LatencySpikes.xcodeproj` builds one iPad app with three modes:

| Mode | What it does |
|---|---|
| PencilKit | A `PKCanvasView` with a white monoline pen on black. |
| Custom | A `CAMetalLayer` view, `UIUpdateLink` with low-latency dispatch and immediate presentation, coalesced and predicted touches, the 1€ filter, and capsule rendering. |
| Hybrid | A `PKCanvasView` at zoom 1 draws the live stroke. At pencil lift, the stroke moves to the Metal renderer of `Custom`. The stroke leaves the `PKCanvasView` after the Metal frame is on the glass. The pen width of PencilKit is the pen width times the zoom. |

The pen width is 2 points. This is a test value only. The product documents do not fix the pen width.

## Run the app

1. Open `Spikes/LatencySpikes.xcodeproj` in Xcode 27.
2. Select a 120 Hz iPad Pro as the run destination.
3. Select the Release configuration in the scheme (Product > Scheme > Edit Scheme > Run > Build Configuration).
4. Run the app.

The launch argument `-mode 0`, `-mode 1`, or `-mode 2` selects PencilKit, Custom, or Hybrid at launch.

## Controls

| Control | Effect |
|---|---|
| Transaction | `CAMetalLayer.presentsWithTransaction`. A change clears the log. |
| Low latency | `wantsLowLatencyEventDispatch` and `wantsImmediatePresentation` of the `UIUpdateLink`. A change clears the log. |
| 1€, min Hz, beta | The 1€ filter of `Custom`. The derivative cutoff stays at 1 Hz. |
| zoom | The camera zoom of `Hybrid`, from 0.25 to 8. `Custom` always draws at zoom 1. |
| Save log | Writes CSV files to Files > On My iPad > LatencySpikes. |

## Measure with the camera

1. Put the iPad flat. Put the camera above it at 240 fps or more.
2. Draw straight lines at a constant speed. Draw 10 lines for each mode and each setting.
3. In the video, find a frame in the middle of a line. Measure the distance from the pencil tip to the end of the ink, in pixels.
4. Measure the distance that the tip moves between two video frames, in pixels.
5. Calculate the latency: distance from tip to ink, divided by the tip movement per frame, times the frame interval. The pixel units cancel, so no ruler is necessary.
6. Use the median of the 10 lines.

The predicted tail of `Custom` makes the ink reach closer to the tip. The camera result includes the prediction and the lag of the 1€ filter. The presented-time log does not include them.

## Read the presented-time log

`Custom` and `Hybrid` show live numbers at the bottom of the screen. `Save log` writes these files:

| File | Content |
|---|---|
| `frames.csv` | One row per presented frame with new pencil samples. `latencyMs` is `presentedTime` minus the `UITouch.timestamp` of the newest sample. `cpuMs` is the time from the first touch handler to the end of command encoding. |
| `clock.csv` | The `UITouch.timestamp` of each event and `CACurrentMediaTime()` in the handler. |
| `handoffs.csv` | One row per hybrid handoff: the time from the drawing change to the Metal frame, and the pixel comparison. |
| `summary.txt` | The text on the screen. |

If all three clock lines on the screen show small positive values below about 20 ms, the clock test passes:

- `now-touch`: `CACurrentMediaTime()` in the handler minus `UITouch.timestamp`.
- `handler-presented`: `CACurrentMediaTime()` in the presented handler minus `presentedTime`.
- `presented-estimated`: `presentedTime` minus `UIUpdateInfo.estimatedPresentationTime`. This value can also be a small multiple of 8.3 ms.

If one value is very large or negative, the two clocks are different.

The hybrid handoff line compares the PencilKit image of the stroke with the Metal image of the same stroke. `max diff` is the largest pixel difference out of 255. `pixels > 25%` counts the pixels that differ by more than 64. `ink metal/pk` is the ratio of the total ink brightness, so a value above 1 means that the Metal stroke is wider. Make sure that you test the handoff at zoom 0.25, 1, and 4.

The simulator has no presented time. On the simulator, the latency numbers are not valid.
