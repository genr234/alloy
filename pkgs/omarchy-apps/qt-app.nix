# Builder shared by Omarchy's Qt Quick apps (hype, monologue, omacalc, omacut,
# omawrite, signed). Each is a qmake project whose bin/build runs qmake6 + make
# and leaves build/<name>; the PKGBUILDs install that binary plus the icon and
# .desktop file from pkgbuild/. Same here, with Nix's qmake setup hook.
{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  pkg-config,
}:

{
  pname,
  version,
  owner ? "omacom",
  hash,
  description,
  qtModules ? [ ],
  buildInputs ? [ ],
  # Programs the app runs through QProcess (ffmpeg, wl-copy, ...).
  runtimePath ? [ ],
  extraInstall ? "",
}:

stdenv.mkDerivation {
  inherit pname version;

  src = fetchFromGitHub {
    inherit owner hash;
    repo = pname;
    tag = "v${version}";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
    pkg-config
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
    qt6.qtsvg
    qt6.qtimageformats
  ]
  ++ map (m: qt6.${m}) qtModules
  ++ buildInputs;

  # qmake reads the .pro in the source root, as bin/build does.
  qmakeFlags = [ "${pname}.pro" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 ${pname} $out/bin/${pname}
    install -Dm644 pkgbuild/${pname}.svg $out/share/icons/hicolor/scalable/apps/${pname}.svg
    install -Dm644 pkgbuild/${pname}.desktop $out/share/applications/${pname}.desktop
    install -Dm644 LICENSE $out/share/licenses/${pname}/LICENSE
    ${extraInstall}
    runHook postInstall
  '';

  qtWrapperArgs = lib.optionals (runtimePath != [ ]) [
    "--prefix PATH : ${lib.makeBinPath runtimePath}"
  ];

  meta = {
    inherit description;
    homepage = "https://github.com/${owner}/${pname}";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = pname;
  };
}
