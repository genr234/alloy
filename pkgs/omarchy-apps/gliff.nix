# gliff: Hyprland remote desktop over SSH (GTK4 client, server and probe).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  makeWrapper,
  gtk4,
  libadwaita,
  libdrm,
  libgbm,
  libva,
  libxkbcommon,
  dbus,
  wayland,
  vulkan-loader,
  openssh,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gliff";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "gliff";
    tag = "v${finalAttrs.version}";
    hash = "sha256-niJDyzNyKW5FVmilPnIodYMjjS2WgLhYsPM4hrnjlK8=";
  };

  cargoHash = "sha256-9CwzmHVK78xIQIuqxxMi3roclJmdCmfug6Bp2BKkKCI=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
    makeWrapper
  ];
  buildInputs = [
    gtk4
    libadwaita
    libdrm
    libgbm
    libva
    libxkbcommon
    dbus
    wayland
  ];

  doCheck = false;

  postInstall = ''
    install -Dm644 pkgbuild/gliff.svg $out/share/icons/hicolor/scalable/apps/gliff.svg
    install -Dm644 pkgbuild/gliff.desktop $out/share/applications/gliff.desktop
  '';

  # Vulkan and VA-API are opened at run time; the client shells out to ssh.
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          vulkan-loader
          libva
          wayland
        ]
      }
      --prefix PATH : ${lib.makeBinPath [ openssh ]}
    )
  '';

  meta = {
    description = "Hyprland remote desktop over SSH (GPU H.264, 4:4:4)";
    homepage = "https://github.com/omacom/gliff";
    license = with lib.licenses; [
      mit
      bsd2
    ];
    platforms = lib.platforms.linux;
    mainProgram = "gliff";
  };
})
