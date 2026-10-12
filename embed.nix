{
  bun2nix,
  bun,
  makeWrapper,
  ...
}:
bun2nix.mkDerivation {
  pname = "timeline-embed";
  packageJson = ./package.json;

  src = builtins.path {
    path = ./.;
    name = "timeline";
  };

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  nativeBuildInputs = [ makeWrapper ];

  # One bundle with moment and the loaders inlined, so the service's closure
  # is bun and a file rather than the whole node_modules Parcel needs.
  buildPhase = ''
    runHook preBuild

    bun build --target=bun --outfile=embed.js src/embed/server.ts

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    bun test

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 embed.js $out/lib/timeline-embed/embed.js
    makeWrapper ${bun}/bin/bun $out/bin/timeline-embed \
      --add-flags "run $out/lib/timeline-embed/embed.js"

    runHook postInstall
  '';

  meta.mainProgram = "timeline-embed";
}
