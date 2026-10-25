# aether: Omarchy's theme maker. Upstream's PKGBUILD installs the release
# binary (a Wails app) rather than building it, and so does this.
{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
  wrapGAppsHook3,
  gtk3,
  webkitgtk_4_1,
  glib-networking,
}:

let
  version = "4.32.0";
  src = fetchFromGitHub {
    owner = "omacom";
    repo = "aether";
    tag = "v${version}";
    hash = "sha256-Ntu2KRcEPyC4SvlFxW8PgdvijqH8OjljF60UuCvnWzg=";
  };
in
stdenv.mkDerivation {
  pname = "aether";
  inherit version src;

  bin = fetchurl {
    url = "https://github.com/omacom/aether/releases/download/v${version}/aether-linux-amd64";
    # sha256sums_x86_64 from the PKGBUILD.
    hash = "sha256:c705a4abef734b17ae37cdbff58a9a796517e6aa5f93ef18b68e3ee99d547ff9";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
  ];
  buildInputs = [
    gtk3
    webkitgtk_4_1
    glib-networking
  ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  # Wrapped by hand after autoPatchelf so GTK/WebKit find their schemas and
  # TLS modules.
  dontWrapGApps = true;
  postFixup = ''
    wrapProgram $out/bin/aether "''${gappsWrapperArgs[@]}"
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 $bin $out/bin/aether
    install -Dm644 build/linux/aether.desktop $out/share/applications/aether.desktop
    install -Dm644 li.oever.aether.url-handler.desktop $out/share/applications/li.oever.aether.url-handler.desktop
    install -Dm644 icon.png $out/share/pixmaps/aether.png
    install -Dm644 assets/aether-icon-512.png $out/share/icons/hicolor/512x512/apps/aether.png
    runHook postInstall
  '';

  meta = {
    description = "Desktop theming application: extract colours from wallpapers and apply themes";
    homepage = "https://github.com/omacom/aether";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "aether";
  };
}
