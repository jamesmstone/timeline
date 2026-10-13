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

  # @swc/core >= 1.16.17 refuses to unpack its native addon under a cache root
  # whose ancestors another user could write to, which rejects every path in
  # the build sandbox; the sandbox is single-tenant, so the check buys nothing.
  env.SWC_NATIVE_BINDING_CACHE_SKIP_SECURITY_CHECK = "1";

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
