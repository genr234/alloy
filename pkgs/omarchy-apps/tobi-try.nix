# try (tobi/try): fresh directories for every experiment. Not the `try` in
# nixpkgs, which is a different tool (binpash/try).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  ruby,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "tobi-try";
  version = "1.10.1";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "try";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ZSt6LSp0AQTbdN86lJGJPWcx6oFR63AFi4s8Vjr5a5o=";
  };

  buildInputs = [ ruby ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 try.rb $out/lib/tobi-try/try.rb
    install -Dm644 lib/tui.rb $out/lib/tobi-try/lib/tui.rb
    install -Dm644 lib/fuzzy.rb $out/lib/tobi-try/lib/fuzzy.rb
    mkdir -p $out/bin
    ln -s $out/lib/tobi-try/try.rb $out/bin/try
    runHook postInstall
  '';

  meta = {
    description = "Fresh directories for every vibe";
    homepage = "https://github.com/tobi/try";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "try";
  };
})
