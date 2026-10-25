# owe-lockfeed: the Owe.LockFeed QML module Omarchy's lock screen imports.
{
  lib,
  stdenv,
  owe,
  cmake,
  qt6,
}:

stdenv.mkDerivation {
  pname = "owe-lockfeed";
  inherit (owe) version src;

  sourceRoot = "${owe.src.name}/qml-plugin";

  nativeBuildInputs = [ cmake ];
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];
  dontWrapQtApps = true;

  # Upstream installs to lib/qt6/qml; Nix's Qt looks in lib/qt-6/qml.
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "\''${CMAKE_INSTALL_LIBDIR}/qt6/qml" '${qt6.qtbase.qtQmlPrefix}'
  '';

  cmakeFlags = [ (lib.cmakeBool "BUILD_TESTING" false) ];

  meta = removeAttrs owe.meta [ "mainProgram" ] // {
    description = "Lock screen video feed module for the OWE wallpaper engine";
  };
}
