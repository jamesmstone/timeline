{
  bun2nix,
  nodejs,
  ...
}:
bun2nix.mkDerivation {
  packageJson = ./package.json;

  # Parcel names its bundles after the source directory, so keep that name
  # out of the store hash.
  src = builtins.path {
    path = ./.;
    name = "timeline";
  };

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  nativeBuildInputs = [ nodejs ];

  # Parcel's prebuilt napi bindings dlopen libstdc++, which bun — unlike
  # node — does not already have loaded.
  buildPhase = ''
    runHook preBuild

    node node_modules/.bin/parcel build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';
}
