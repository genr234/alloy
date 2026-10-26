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

On Windows, download `alloy.img.zst` from the
[releases](https://github.com/genr234/alloy/releases) and flash it with
balenaEtcher or Rufus.

New releases come from the Release workflow: push a `v*` tag, or run it by hand
from the Actions tab.
