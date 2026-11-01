# Alloy

Custom Linux I made for my ps5 based on NixOS borrowing things from Omarchy

## Install

Plug a USB drive into your computer (Linux or macOS) and run:

```sh
curl -fsSL https://raw.githubusercontent.com/genr234/alloy/main/install.sh | bash
```

It downloads the latest release image, checks it, asks which drive to use and
writes the image there. **The drive is erased.** Then plug it into the PS5 and
start the ps5-linux loader.

Options go after `bash -s --`, for example
`curl -fsSL .../install.sh | bash -s -- --build`:

- `--build` builds the image with Nix instead of downloading a release
- `--image FILE` flashes an `alloy.img` or `alloy.img.zst` you already have
- `--release TAG` picks a release other than the latest
- `--device DEV` skips the drive menu (it still asks before erasing)

On Windows, download the `alloy.img.zst.*` parts from the
[releases](https://github.com/genr234/alloy/releases) (GitHub caps each file at
2 GiB), join them in a Command Prompt in that folder, and flash the result with
balenaEtcher or Rufus:

```bat
copy /b alloy.img.zst.00 + alloy.img.zst.01 + alloy.img.zst.02 alloy.img.zst
```

List every part the release has, in order.

New releases come from the Release workflow: push a `v*` tag, or run it by hand
from the Actions tab.

## Game mode

Press Super+G, pick Game Mode in the menu, or hold PS on a controller to get
Steam Big Picture. Steam's Power menu takes you back to the desktop, or shuts
down and restarts the console.

### Rest mode

The PS5 can't suspend under Linux, so rest mode does the next best thing: the
screen turns off and boost turns off, while Steam keeps downloading (and so do
Decky plugins such as Tender). Press PS, or switch a controller back on, to wake
it up into game mode.

- Start it from the Alloy panel in Steam's Quick Access menu (the `...`
  button), from Rest Mode in the desktop menu, or with `alloy-mode rest`.
- Game mode goes into rest by itself after 30 minutes without controller input,
  but never while a game is running.
- When every download is done, the console shuts down: Steam's download queue
  has to be empty (downloads you paused don't count), so does aria2's (see
  Downloads below, archives included), and the network has to
  stay quiet for 10 minutes, so Tender's downloads finish too. Traffic from
  containers doesn't count as downloading.

Rest mode closes the game that's running, since the PS5 can't pause it. The
Alloy panel can switch auto-rest and the shutdown off;
`alloy.modes.rest` in `hosts/ps5` sets the defaults.

### Downloads

Downloads from the browser stop when the desktop closes for rest mode, so big
ones go to **aria2** instead: a download manager that runs as a background
service (`alloy-downloads`). It splits each file over several connections,
like IDM, resumes after a reboot, and rest mode waits for it before shutting
down.

- **From the browser:** install the *Aria2 Explorer* extension, and in its
  settings set the RPC address to `http://127.0.0.1:6800/jsonrpc` and the
  secret to what `alloy-download secret` prints. Downloads you start in the
  browser then go to aria2. On file-host pages (FuckingFast, DataNodes and
  the like) just press their download button.
- **From a terminal:** `alloy-download URL...`, or
  `alloy-download -i links.txt` with one direct link per line.
- **Watch them:** the **Downloads** app (AriaNg), or `alloy-download status`.

Files go to `~/Downloads`. When the last part of a split archive arrives
(`name.part01.rar` ... `name.part20.rar`, `name.7z.001` ..., or a single
`.rar`/`.7z`/`.zip`), it's extracted next to the parts. A set with a missing
or broken part, or a password, is left as it is (see
`journalctl --user -u alloy-downloads`). `alloy-download extract` tries again
by hand. Set `alloy.modes.downloads.deleteArchives` to delete the parts after
extracting.

So for a big download: queue every part, press **Rest now** (or pick Rest Mode
in the desktop menu), and leave. The console powers off once the parts are
downloaded and extracted, and Steam's queue is empty.

### Decky plugins

Decky Loader adds plugins to the Quick Access menu. Alloy installs its own
panel. Install the others once from Decky's settings (the gear in the Decky
tab):

- **Tender**: your RomM library inside Steam, with downloads, BIOS files and
  save sync. Needs RomM 5.3 or newer. Turn on Developer mode, then go to
  Developer, choose Install Plugin from URL, and paste the latest zip from
  [romm-tender's releases](https://github.com/danielcopper/romm-tender/releases).
  Games launch through RetroDECK, which Alloy installs from Flathub in the
  background on first boot.
- **Decky Framegen**: OptiScaler per game, from the Decky store. Use it for
  FSR 4 (pick the *Valve RDNA2 Compatibility* runtime on the PS5), FSR 3.1
  frame generation and XeSS. Add the launch option it gives you to each game
  you want it on.
- **lsfg-vk**: Lossless Scaling frame generation for almost any game, from the
  Decky store. Needs Lossless Scaling on Steam: buy it, set its beta branch to
  `lsfg-vk` (Properties > Betas), then press Install in the plugin. It doesn't
  work with VRR, and can clash with the performance overlay.

Steam's own scaling filter (FSR 1, NIS, integer, per game) is under
Performance in the Quick Access menu.

## Updates

`nixos-rebuild switch` applies an update right away, without a reboot.
Services restart, and the session moves to the new desktop, game and rest
scripts the next time you change modes.

An update that changes the kernel (the PS5 patches, the Wi-Fi driver, kernel
parameters) still has to restart into it. Alloy does that with kexec, which
takes a few seconds and skips the PS5 loader:

- on its own, the next time the console goes into rest mode (it then carries
  on resting)
- from the Restart to finish update button in the Alloy panel, or the
  notification on the desktop
- with `alloy-update finish`

If the new kernel doesn't reach a working session, the next boot falls back to
the previous generation, as with any other boot.
