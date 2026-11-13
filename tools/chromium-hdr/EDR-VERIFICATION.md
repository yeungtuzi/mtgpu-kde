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
- `GetHdrHeadroom()` is log2 of the relative luminance: `1.32193` = 2.5x,
  `2.59074` = 6.02x, both of which are the 500 nit peak at the SDR white of the
  moment (200 nit at 100 %, 83 nit at 40 %).
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

## Surface-level target_luminance (resolved)

The client also receives the panel peak.  KWin's own log (temporary `EDRK`
instrumentation in `ImageDescriptionV1::wp_image_description_v1_get_information`)
shows the descriptions it sends carry `ref=200 tf_max=500 hdr_max=500`, and
Chromium's `[EDR] swap` line reports `headroom=1.32193` at that SDR white, which
is `log2(500/200) = 2.5x`.  At 40 % brightness the same peak gives
`log2(500/83) = 2.59x`.  No surface-level gap exists; the earlier claim came
from reading the log2 value as a linear ratio.

## Reference white follows the slider (outdoor use)

With the KWin patch the slider drives the **SDR reference white** and can reach
the panel peak, which is the behaviour a user expects when they deliberately
give up HDR headroom for legibility outdoors:

| slider | reference white | panel peak | headroom |
|---|---|---|---|
| 100 % | 500 nit | 500 nit | 1.00x (`GetHdrHeadroom()` = 0) |
| 40 % | 203 nit | 500 nit | 2.46x (= 1.30 in log2) |

Measured with `edr-probe` (`LUMINANCES reference`) and Chromium's
`[EDR] swap` line (`headroom=0 sdr_nits=500` at 100 %, `headroom=1.30045
sdr_nits=203` at 40 %).  At 100 % there is no HDR headroom left by design;
lower the slider to regain it.

## BT.2390 EETF roll-off into the 500 nit panel (LUT)

Advertised peak and actual rendering are now separated:

* clients are told the display peak is 500 nit (`target_luminance`), so they send
  HDR1000 content untouched;
* the compositor maps that content into `[0.0005, 500]` nit with an ITU-R
  BT.2390 EETF instead of clipping at 500.

The curve is precomputed on the CPU per pipeline and uploaded as a **129-entry
1D LUT in the PQ domain** (`uniform float tonemapLut[129]`); the fragment shader
does one `floor`/`mix` lookup, so there is no per-pixel `pow` or branch.

Parameters: source black 0.05 nit, source peak = content peak (1000 nit for a
typical HDR10 grade), destination black 0.0005 nit, destination peak 500 nit.

Measured/derived mapping for a 500 nit panel:

| source | output |
|---|---|
| 100 nit | 65.5 nit |
| 203 nit | 135.4 nit |
| 500 nit | 338.5 nit |
| 1000 nit | 500.0 nit |
| 4000 nit | 500.0 nit |

Consequences: 500 nit and 1000 nit bars are now distinct (338 vs 500) instead of
both clipping at 500, at the cost of darker mid-tones; the SDR reference white
still follows the brightness slider, while the HDR mapping does not.

## Measured behaviour (2026-11-11, BT.2390 LUT + fixed 1000 nit client target)

Compositor side, with the client-facing HDR target decoupled from the panel peak:

* KWin advertises a **fixed 1000 nit** HDR target (`target_luminance`) to every
  client, independent of the brightness slider;
* KWin renders into the real 500 nit panel peak and applies the BT.2390 EETF
  (129-entry PQ LUT) with `maxWhite=1000 -> maxOut=500`, again independent of the
  slider.

Verified with `hdr-bars-vp9.webm` in the self-built Chromium:

| slider | Chromium headroom | KWin video pipeline |
|---|---|---|
| 100 % | 1.00 (= 1000/500) | `tonemap=1 maxWhite=1000 maxOut=500` |
| 40 % | 2.30 (= 1000/203) | `tonemap=1 maxWhite=1000 maxOut=500` |

Visual result at ~50 % brightness: the 100 / 203 / 500 / 1000 nit bars are all
distinct (500 nit renders at ~338, 1000 nit at 500), i.e. the roll-off works and
there is no hard clip at the panel peak.

### Known limitation: the video still follows the brightness slider

Raising the slider towards 100 % visibly brightens the HDR clip -- bar 3 climbs
towards bar 4 and the two merge at 100 % -- and lowering it towards 0 % dims bar 4.
The compositor's tone mapping is fixed (see the pipeline log above), so the
remaining brightness dependence comes from the final blend/dimming stage of the
SDR composition, not from the EETF.  At 100 % the SDR white reaches the panel
peak, so a 500 nit HDR highlight legitimately coincides with white and the last
bar merges.

This is close to how macOS renders EDR video (the clip is not fully independent
of the UI brightness either) and is considered acceptable for now; making the
HDR plane strictly absolute would require the HDR content to be blended in a
separate linear pass and the software dimming to be applied only to the SDR
plane, which is a larger compositor change.

### Recommended brightness for watching HDR (known limitation)

The usable window is narrow:

| slider | SDR white | HDR result |
|---|---|---|
| < 40 % (~200 nit) | under 200 nit | highlights look dim, the clip loses impact |
| **40-50 % (~200-250 nit)** | 200-250 nit | **correct**: all four bars distinct, 1000 nit still reaches the panel peak |
| > 50 % | above 250 nit | bar 3 climbs towards bar 4 and they merge near 100 % |

So **40-50 % is the recommended setting while watching HDR**, and the
brightness-dependent part is a known issue rather than intended behaviour.

## 免重编 Chromium 的 EDR（2026-11-13 验证）

KWin 侧新增：`wp_image_description_info_v1_send_luminances()` 通告的 **HDR 最大值下限提升到 1000 nit**
（`patches/kwin-6.8.2-edr-advertise-1000.patch`），物理面板峰值仍是 500 ni，由 BT.2390 LUT 压回。

效果：**未改动的 Chromium 系浏览器也能拿到 EDR**，不需要重编客户端。

| 浏览器 | 硬解（VPU） | EDR | 证据 |
|---|---|---|---|
| Brave 1.99.57（Chromium 157） | ✅ 默认（2.8–6.0%） | ✅ | `EDRK shader tonemap=1 maxWhite=1003.2 maxOut=500.0 tf=2` |
| Google Chrome（预装） | ✅ 默认 | ✅ | 同上 |
| 本仓 mtgpu-chromium | ✅ | ✅ | 同上 |

探针读数（`tools/edr-probe`）：`LUMINANCES min=0.01 max=1000 reference=153`、`TARGET_LUM min=0.01 max=1000`。
