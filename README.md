# BeamNG HandPaint

Paint directly on a vehicle, save an editable design, preview it on another supported vehicle, then apply it. Includes single-player operation and a BeamMP server plugin for synchronized painting and late-join replay.

### Installation

For **single-player**, copy the ZIP to the `mods` directory of the active BeamNG user folder. Find that folder through the BeamNG launcher rather than the Steam installation directory.

### Installation

1. **Download the release**

   * Go to the **Releases** page.
   * Download the latest `.zip` file.

2. **Extract the files**

   * Unzip the download.
   * You will get two folders:

     * `Client`
     * `Server`

3. **Install the client files**

   * Open the extracted **Client** folder.
   * Inside it is a `.zip` file.
   * Upload that `.zip` into your server’s **client mods folder**.

4. **Install the server files**

   * Open the extracted **Server** folder.
   * Inside is a folder for the game mode (e.g. `CarHunt`, `Tag`, `PropHunt` etc.).
   * On your server, open the main **server folder**.
   * Create a folder for that game mode (for example: `CarHunt`, `Tag`, `PropHunt`).
   * Copy **all files** from the extracted game mode folder into the matching folder you just created on the server.

5. **Restart the server**

   * Restart your BeamMP server.
   * The game mode should now be active.

---

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
