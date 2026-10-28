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
