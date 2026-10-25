# ttfx: terminal text effects (Rust port of terminaltexteffects).
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ttfx";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "ttfx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ZeWRyo9zturjRcH23SDgFOKoPOSY6nGMFzGeJAoDapk=";
  };

  cargoHash = "sha256-ntoj5bmAa9U2+3K1UX6HL0t6MjfCYQNe5LuiuNJ/CnY=";

  nativeBuildInputs = [ installShellFiles ];
  doCheck = false;

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd ttfx \
      --bash <($out/bin/ttfx --print-completion bash) \
      --zsh <($out/bin/ttfx --print-completion zsh)
  '';

  meta = {
    description = "Terminal text effects as a single static binary";
    homepage = "https://github.com/omacom/ttfx";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ttfx";
  };
})
