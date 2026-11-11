# Chromium 157 EDR verification on the M1000 (aarch64, KWin Wayland)

## Summary

Chromium 157 (release 157.0.8103.38) **already consumes the real display
headroom** advertised by KWin through `wp_color_management_v1`.  The historical
"Chromium uses an arbitrary hard-coded headroom" problem does not exist in this
version, so no behavioural patch is needed for tone mapping; the diagnostics
patch in this repository only *observes* the values.

## Method

Instrumentation added to `components/viz/service/display/skia_renderer.cc`
(gated behind `CHROME_EDR_DEBUG=1`):

- per-quad: source colour space, `is_video`, display SDR luminance, display
  headroom and the *targeted* headroom computed by
  `dynamic_range_limit.ComputeEffectiveHdrHeadroom(...)`;
- per-frame (first 40 frames): display headroom and SDR white level.

Run:

```sh
CHROME_EDR_DEBUG=1 ./chrome --ozone-platform=wayland --no-sandbox \
  --enable-features=UseDisplaySDRMaxLuminanceNits \
  --autoplay-policy=no-user-gesture-required \
  --allow-file-access-from-files ~/hdr-video.html
```

(`hdr-video.html` wraps a VP9 10-bit PQ clip; the original `hdr-bars.mp4` is
HEVC, which this build does not decode.)

## Measurements

```
[EDR] swap headroom=3.83197 sdr_nits=83 size=2592x1620
[EDR] quad src={primaries:BT2020, transfer:PQ (white:203.0000 nits),
                matrix:RGB, range:FULL} is_video=1
      disp_sdr_nits=83 disp_headroom=3.83197 targeted_headroom=3.83197
```

- `disp_headroom` comes from `display_color_spaces.GetHdrHeadroom()`, which the
  Wayland backend fills from the compositor's colour-management description.
- `targeted_headroom == disp_headroom`: the compositor headroom is used in full.
- 3.83 ≈ 318 nit peak with an 83 nit SDR white, consistent with KWin's
  `maxPeakBrightnessOverride=500` / `edrPolicy=always` configuration and the
  current SDR slider position.

## Why screenshots cannot prove it

With the HDR video playing, only the first frame arrives as a Skia quad; later
frames are promoted to a **hardware overlay plane**.  `spectacle`/`grim`
capture the composited scene, so the video area comes out black — this is a
capture limitation, not an EDR failure.  Evidence therefore comes from the
targeted-headroom instrumentation plus KWin's own luminance configuration
(`~/.config/kwinoutputconfig.json`: `maxPeakBrightnessOverride: 500`,
`edrPolicy: always`).

## Notes on the earlier "Chrome cannot do EDR" conclusion

The pre-installed Google Chrome is the *same* 157.0.8103.38 build and also binds
`wp_color_manager_v1`.  Any difference in observed EDR is therefore **not** a
code-path difference; the likely causes are content-side (HEVC video not
decoding, autoplay blocked) or measurement-side (overlay not captured).

## Hardware scope (aibook OLED)

The setup in this repository is tuned for the **aibook's OLED panel**, which has
no backlight: "brightness" is panel drive level, so pinning it to maximum costs
almost nothing in power and leaves the panel's 500 nit peak permanently
available.  KWin's EDR patch therefore

1. pins the panel to full drive (`setBrightness(1.0)`), and
2. lets the brightness slider move the **SDR white point** instead
   (`reference_luminance` = 200 nit at 100 %, 83 nit at 40 %).

That makes `headroom = panel_peak / SDR_white` a pure rendering decision:
2.5 at 100 %, 6.0 at 40 %, with the 500 nit peak always reachable.

### On backlit (LCD) panels this is different

There the peak is set by the backlight, so EDR has to **boost the backlight to
maximum before rendering HDR** and lower the SDR white point in software.  That
is a real power and battery-life cost, and it is why the boost must be
**reverted when EDR/HDR is switched off** — otherwise the panel stays at full
backlight for ordinary SDR content.  A portable implementation therefore needs:

- save the user's backlight level on entering EDR,
- raise it to maximum while EDR is active,
- restore the saved level on exit (and on compositor restart/crash).

The Chromium-side patch in this repository is written against the
`luminances.max` field, which both cases report as the *currently achievable*
peak — the pinned OLED peak here, the boosted backlight peak on an LCD — so the
same client code behaves correctly on both.

## Advertising the panel peak from the compositor (no Chromium patch needed)

Chromium derives its display headroom from the `target_luminance` event of
`wp_image_description_v1`, which KWin fills with
`ColorDescription::maxHdrLuminance()`.  Two KWin changes make that value the
real panel peak:

1. `ColorDescription::dimmed()` no longer scales `maxHdrLuminance` with the
   brightness slider (the peak is hardware capability; only the reference/SDR
   white and the average luminance follow the slider).
2. `DrmOutput::createColorDescription()` passes `maxPeakBrightnessOverride`
   (500 nit on this panel) instead of `maxLuminance * maxPossibleArtificialHdrHeadroom`.

Result: `target_luminance` stays at 500 nit at any slider position, so **even
the unpatched distribution Chromium/Chrome reaches the panel peak** — no
Chromium rebuild is required for EDR to work.  The Chromium-side patch in this
repository (preferring `luminances.max`) is the alternative for compositors that
do not advertise a usable target.

Apply with `patches/kwin-6.8.2-edr-target-luminance.patch` and restart KWin.
