# Omarchy's own apps: what basecamp/omarchy installs from its own package
# repo (omacom-io/omarchy-pkgs) rather than from Arch. Versions and build steps
# follow those PKGBUILDs; the sources are the same release tags, so each
# `hash` here is the PKGBUILD's tarball unpacked.
#
# To update one: bump `version`, set `hash = lib.fakeHash;`, build, and paste
# the hash Nix prints.
{ pkgs }:

let
  inherit (pkgs) lib;
  qtApp = pkgs.callPackage ./qt-app.nix { };
in
lib.makeScope pkgs.newScope (self: {
  hype = qtApp {
    pname = "hype";
    version = "0.6.0";
    hash = "sha256-lDrDfo0LqGbWD8X7rejOYf9nKqyNNZh6wMlL9wRRJoU=";
    description = "Markdown presentations with a visual slide editor";
    qtModules = [ "qtmultimedia" ];
    buildInputs = with pkgs; [
      zlib
      libwebp
    ];
    runtimePath = with pkgs; [
      ffmpeg
      sourceHighlight
      wl-clipboard
    ];
  };

  monologue = qtApp {
    pname = "monologue";
    version = "0.3.1";
    hash = "sha256-sQm/n0kHl13JQ3iOcOM5rZcP9xqrPpw6EKTVBLWha/I=";
    description = "A simple, theme-synced webcam recorder for Omarchy";
    qtModules = [ "qtmultimedia" ];
    buildInputs = [ pkgs.libpulseaudio ];
    runtimePath = [ pkgs.ffmpeg ];
  };

  omacalc = qtApp {
    pname = "omacalc";
    version = "0.3.1";
    owner = "omacom-io";
    hash = "sha256-Q1LGLTmMz8jqPGptyp8oZKr3iCM2YTR0f/NbmPY8AFQ=";
    description = "Dead-simple calculator built with Qt Quick";
  };

  omacut = qtApp {
    pname = "omacut";
    version = "0.7.2";
    hash = "sha256-bNu2S0BPDCjm9PQQUCSC7UGuACpP9vXbbHILlaSoI0s=";
    description = "Dead-simple video length trimmer built with Qt Quick and ffmpeg";
    qtModules = [ "qtmultimedia" ];
    runtimePath = [ pkgs.ffmpeg ];
  };

  omawrite = qtApp {
    pname = "omawrite";
    version = "0.7.2";
    hash = "sha256-kjbiI5Wo/vX9Fs3XnN1K3PWPOtOIX85ZLFOL1HBl6t0=";
    description = "Dead-simple Markdown writing app built with Qt Quick";
    runtimePath = [ pkgs.wl-clipboard ];
  };

  signed = qtApp {
    pname = "signed";
    version = "0.3.1";
    hash = "sha256-fH5jXdO0uNsRblramzU0lcP3Dvv7pMZjf41FdE3lKjY=";
    description = "Sign PDFs and fill them in with text and dates";
    buildInputs = [
      pkgs.kdePackages.poppler
      pkgs.qpdf
    ];
  };

  gliff = self.callPackage ./gliff.nix { };
  ttfx = self.callPackage ./ttfx.nix { };
  omasnap = self.callPackage ./omasnap.nix { };
  owe = self.callPackage ./owe.nix { };
  owe-lockfeed = self.callPackage ./owe-lockfeed.nix { };
  omarchy-hyprland-titlebars = self.callPackage ./titlebars.nix { };
  aether = self.callPackage ./aether.nix { };
  omarchy-nvim = self.callPackage ./omarchy-nvim.nix { };
  tobi-try = self.callPackage ./tobi-try.nix { };
})
