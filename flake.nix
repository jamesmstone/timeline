{
  description = "James Stone's timeline — timeline.jamesst.one";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";

    # Left unfollowed on purpose: duckweb pins its own nixpkgs and toolchains
    # against the DuckDB version its extensions are built for.
    duckweb.url = "git+ssh://forgejo@hermanii/james/duckweb";

    # The site's markup and styles come from this library; its `css` package
    # is the bundled stylesheet plus the web fonts it builds.
    design = {
      url = "git+ssh://forgejo@hermanii/james/design";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    inputs:
    let
      eachSystem = inputs.nixpkgs.lib.genAttrs (import inputs.systems);

      pkgsFor = eachSystem (
        system:
        import inputs.nixpkgs { inherit system; }
      );

      # The duckweb extensions this flake builds are x86_64-linux only.
      siteSystems = [ "x86_64-linux" ];
      onSiteSystems = system: lib.optionalAttrs (builtins.elem system siteSystems);
      lib = inputs.nixpkgs.lib;

      sitePackages =
        system:
        let
          pkgs = pkgsFor.${system};
          duckweb = inputs.duckweb.packages.${system};

          # DuckDB ships sqlite_scanner as a download rather than a build output.
          # DuckDB derives the entrypoint symbol from the file name, so the
          # store path cannot be the extension itself.
          sqliteScanner = pkgs.runCommand "sqlite_scanner" { } ''
            mkdir -p $out
            ${pkgs.gzip}/bin/gunzip -c ${
              pkgs.fetchurl {
                url = "http://extensions.duckdb.org/v2.0.0/linux_amd64/sqlite_scanner.duckdb_extension.gz";
                hash = "sha256-Wbigum11mdSqWEvSTotMwyRwdrsXQVf0PhEOVubHLoY=";
              }
            } > $out/sqlite_scanner.duckdb_extension
          '';

          # Quack serves the private instance's catalogs to other DuckDBs, and
          # needs httpfs loaded beside it. Both ship as downloads, like the
          # scanner, and carry the same entrypoint-from-filename constraint.
          fetchExtension =
            name: hash:
            pkgs.runCommand name { } ''
              mkdir -p $out
              ${pkgs.gzip}/bin/gunzip -c ${
                pkgs.fetchurl {
                  url = "http://extensions.duckdb.org/v2.0.0/linux_amd64/${name}.duckdb_extension.gz";
                  inherit hash;
                }
              } > $out/${name}.duckdb_extension
            '';
          quack = fetchExtension "quack" "sha256-+aXA0uDu8PdUarpFeauA110WfN9IgwRZ+vZzeKsgAP4=";
          httpfs = fetchExtension "httpfs" "sha256-7mx9fmCl2htva/YVa0KYtV3c4ElqW/5ii9arbUfrjj4=";

          built = pkgs.callPackage ./nix/site.nix {
            duckdb = duckweb.duckdbStatic;
            inherit sqliteScanner;
            designCss = inputs.design.packages.${system}.css;
            duckwebExtension = "${duckweb.duckweb}/v${duckweb.duckdbStatic.version}/linux_amd64/duckweb.duckdb_extension";
            duckwebWasm = "${duckweb.duckweb-wasm}/v${duckweb.duckdbStatic.version}/wasm_eh/duckweb.duckdb_extension.wasm";
            duckwebAssets = duckweb.duckweb-assets;
            duckwebClient = "${inputs.duckweb}/duckweb/client";
            duckdbVersion = "v${duckweb.duckdbStatic.version}";
          };
        in
        {
          sqlite-scanner = sqliteScanner;
          inherit quack httpfs;
          inherit (built) assets app;
          garmin-public = built.garminPublic;
          garmin-empty = built.emptyGarmin;
          purifier-snapshot = built.purifierSnapshot;
          timeline-export = built.timelineExport;
          app-db = built.appDb;
          family-snapshot = built.familySnapshot;
        };
    in
    {
      # On x86_64-linux `nixosModules.default` carries `services.timeline`, the
      # public instance: duckweb answering from SQL over the public-safe sources,
      # with the lane timeline at `/`; `services.timeline-private`, the tailnet
      # instance over every source, with `/embed.svg` and Quack; and
      # `services.timeline-export`, the per-source DuckDB files. The module does
      # not import duckweb's NixOS module: the instances set `services.duckweb`,
      # so the consuming configuration must import
      # `inputs.duckweb.nixosModules.duckweb` itself.
      packages = eachSystem (
        system:
        onSiteSystems system (sitePackages system)
      );

      nixosModules.default =
        { ... }:
        {
          imports = [
            (import ./site-module.nix {
              self = inputs.self;
              duckweb = inputs.duckweb;
            })
            (import ./export-module.nix { self = inputs.self; })
            (import ./private-module.nix {
              self = inputs.self;
              duckweb = inputs.duckweb;
            })
          ];
        };

      checks = eachSystem (
        system:
        onSiteSystems system {
          site-vm = import ./nix/vm-test.nix {
            self = inputs.self;
            pkgs = pkgsFor.${system};
            inherit system;
            duckweb = inputs.duckweb.packages.${system};
            duckwebModule = inputs.duckweb.nixosModules.duckweb;
          };
          site-assets = inputs.self.packages.${system}.assets;
        }
        // {
          pan = pkgsFor.${system}.runCommand "timeline-pan-test" { nativeBuildInputs = [ pkgsFor.${system}.bun ]; } ''
            cp -r ${./web} web
            bun test web
            touch $out
          '';
        }
      );

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.mkShell {
          packages = [ pkgsFor.${system}.bun ];
        };
      });
    };
}
