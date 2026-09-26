# BeamNG HandPaint

An alpha vehicle painter derived from the painting system in the local **BeamMP-Mecca** project. Paint directly on a vehicle, save an editable design, preview it on another supported vehicle, then apply it. Includes single-player operation and a BeamMP server plugin for synchronized painting and late-join replay.

**Status:** alpha. Live single-player tests confirmed native strokes on the Sunburst wagon, save/reload, transfer to the Covet, and replay after vehicle reload. Native thumbnail capture is also verified. Two-client BeamMP synchronization remains mock-tested only. See [the live test results](docs/verification/2026-09-24.md).

## Build and install

```powershell
.\test.ps1
.\build.ps1
```

Tests require `lua` and `luac` on PATH. The build uses PowerShell and produces:

```text
dist/Resources/Client/BeamNGHandPaint.zip
dist/Resources/Server/BeamNGHandPaint/main.lua
dist/Resources/Server/BeamNGHandPaint/lua/design.lua
```

For **single-player**, copy the ZIP to the `mods` directory of the active BeamNG user folder. Find that folder through the BeamNG launcher rather than the Steam installation directory.

For **BeamMP**, copy the contents of `dist/Resources` into your server's `Resources` directory and restart the server. Clients receive the ZIP on connection. The server plugin is required for multiplayer painting; installing only the client ZIP does not let other players see designs. This follows the [BeamMP 3.x resource layout](https://docs.beammp.com/scripting/server/latest-server-reference/).

Install the updated client **and server plugin** together. Older plugins are reported as unavailable because they cannot preserve grouped strokes.

Run HandPaint separately from Mecca's camouflage mode: both use the vehicle's Dynamic Textures material and would compete for the same texture binding.

## Painting and saving

The compact panel has **Paint** and **Designs** tabs. Paint keeps colour swatches, brush shape, size/opacity, mirror, eraser and undo/redo together. Width and rotation are under **Advanced brush settings**, while the operation count and clear action are under **Canvas options**. The window sizes to its contents instead of keeping an empty fixed-height area.

1. Spawn a supported vehicle. The **HandPaint** window opens automatically.
2. Click **Start painting**. This selects the vehicle's Dynamic Textures skin and may respawn it. It replaces the existing livery.
3. Hover to preview the brush's shape, size, opacity, rotation and mirror on the car. Drag the left mouse button to paint. Move the camera to reach other sides. UI controls and other vehicles block brush input.
4. Choose colour, round/soft/square brush, size, opacity, width, rotation and mirroring. Fill, eraser, undo, redo and clear are available.
5. Enter a name and click **Save design**. The name must be new; existing designs are not overwritten. Save again under another name to keep revisions.

Saving also captures a 320x200 thumbnail beside the JSON file. It uses a separate camera and briefly pauses painting. Older designs without an image show a placeholder.

Designs live in the active BeamNG user folder under `settings/handpaint/designs/*.json`. They preserve the base colour, ordered strokes, source model and dimensions. Eraser restores the saved base colour. Saved files survive game/server restarts; unsaved server paint does not.

Press **Alt+H** to open or close the window. **Ctrl+Z** undoes a complete brush drag; **Ctrl+Y** redoes it. History shortcuts work while HandPaint is visible, outside text fields and the World Editor. You can rebind the HandPaint actions in Controls, or use `extensions.handpaint_main.toggle()` in the GE Lua console.

## Applying a design to another vehicle

1. Switch to or spawn the target vehicle you own.
2. Open **Designs** and choose a saved design. Use **Search by name** to filter the thumbnail library. Opening this tab pauses the brush.
3. Click **Preview on this vehicle**. Inspect every side using the camera.
4. Open **Adjust fit and placement**, adjust scale and left/right, front/back or up/down placement. The preview refreshes after adjustments settle; **Reset fit** restores the starting placement.
5. Click **Apply design** (single-player) or **Apply and synchronize** (BeamMP) to commit, or **Cancel preview** to restore the current HandPaint design/base.

Preview paint is local. Preparing the Dynamic Textures skin is an ordinary vehicle configuration change and can be visible to other BeamMP players before the design is committed. Cancelling a preview restores the current HandPaint paint/base, not the vehicle's original non-HandPaint skin.

Transfers use a uniform fit based on source and target vehicle bounds. This preserves brush shapes but **does not match individual body panels**. Designs can stretch across different panels, miss surfaces or need touch-ups on vehicles with different proportions. The original saved design stays unchanged. Apply, touch up, and save another version if desired.

## Autosave and recovery

Local checkpoints are written every five seconds while there are edits, at the end of a brush drag, after undo/redo, and when the extension unloads or the mission ends. They include pending local brush operations awaiting BeamMP acknowledgement. Two alternating files keep a previous valid checkpoint if the latest write is interrupted. An abrupt exit can still lose changes since the last successful checkpoint.

Open **Designs > Recover unfinished designs**, choose **Recover**, inspect the preview, then apply and save with a name. Recovery never automatically replaces the current car's design. **Discard** removes that checkpoint pair. Files are stored under `settings/handpaint/recovery/`, separately for each session, vehicle and model.

The header shows **Connecting**, **Syncing**, **Synced with server**, or **Unavailable**. Synced means the server acknowledged the design; it does not confirm every remote player's renderer has finished. A missing acknowledgement triggers a resync attempt and preserves a local checkpoint.

## Vehicle support and limits

The runtime checks for a paint-design slot, an enabled stock Dynamic Textures skin, and compatible body materials. See the [asset inventory inherited from Mecca](docs/vehicle-support.md). It lists many vanilla models, but is not a live rendering certification. MD-Series and Rock Bouncer had disabled stock skins in that inventory. Unsupported vehicles display a reason instead of being force-enabled.

- Up to 3,000 paint operations per vehicle. A held brush can produce 30 operations per second; smoothing adds intermediate stamps.
- BeamMP owns the accepted history, validates ownership and stroke data, and replays designs for joining clients.
- Large saved designs upload in chunks; the server commits only when the complete upload arrives. Wait for synchronization before saving or changing the design.
- Undo/redo groups newly painted operations by mouse drag. Legacy saved strokes without group IDs undo individually. Applying a saved design starts a new history; save the previous design first if you want to keep it.
- Reset/respawn replay retains paint for the same model. Changing model clears active paint; explicitly choose a saved design to transfer it.
- There is no exported static vehicle skin ZIP, permanent server-side design library or automatic loading of paint from a `.pc` configuration in this alpha.

## Shader compatibility

The default build includes Mecca's one-line Dynamic Decals DirectX 12 shader fix, based on the locally installed BeamNG 0.39.4.0 shader. It changes the `SV_POSITION` input interpolation qualifier to `noperspective centroid`. The installed original was checked on 2026-09-24 and has SHA256 `98A45DD205BB9B35A8F4EAC275C2C8B2DA5F2113A90634663B9AFB2F67B5CE66`.

The ZIP mounts an override; the build does not edit the game installation. Review this compatibility file after a game update. Use `./build.ps1 -SkipShaderFix` to produce a ZIP without it. The live DirectX 12 test used an existing, byte-identical loose shader override in the user's folder, so delivery of the fix from this ZIP alone remains unverified.

## Verification

`test.ps1` checks Lua syntax and exercises design validation, fit maths, source immutability, save/reload failures, interrupted recovery writes, drag boundaries, text-input shortcut protection, the client editor flow, native-renderer calls with mocks, vehicle picking, skin queues, brush smoothing and server history/upload/ownership logic. A client integration test connects the real editor controller to the real server handlers using a mock transport.

Follow [the live test checklist](docs/live-test.md) before treating this as ready for multiplayer use.

## Source provenance

The renderer, skin detection, queued-skin handling, ray picker, smoothing, brush textures and shader compatibility file were adapted/copied from `../BeamMP-Mecca`. HandPaint adds its own controller, versioned saved-design format, local library, fitting controls, server protocol and tests. No Mecca gameplay rules or taunt audio are included. The shader originates from the installed game; no new license is asserted over inherited files.
