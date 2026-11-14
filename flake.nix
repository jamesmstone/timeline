{
  description = "James Stone's timeline — timeline.jamesst.one";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";

    # Keep in step with the bun2nix that generated bun.nix.
    bun2nix.url = "github:nix-community/bun2nix?tag=2.1.2";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";

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
        import inputs.nixpkgs {
          inherit system;
          overlays = [ inputs.bun2nix.overlays.default ];
        }
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

          built = pkgs.callPackage ./nix/site.nix {
            duckdb = duckweb.duckdbStatic;
            inherit sqliteScanner;
            designCss = inputs.design.packages.${system}.css;
          };
        in
        {
          sqlite-scanner = sqliteScanner;
          inherit (built) assets app;
          garmin-public = built.garminPublic;
          garmin-empty = built.emptyGarmin;
        };
    in
    {
      # `packages.<system>.default` is the Parcel build: a plain folder of
      # assets, ready to be used as a web server root, e.g.
      #   services.caddy.virtualHosts."timeline.jamesst.one".extraConfig = ''
      #     root * ${inputs.timeline.packages.${system}.default}
      #     file_server
      #   '';
      #
      # `packages.<system>.embed` is the server behind /embed.svg, which a
      # directory cannot answer; run it with `nixosModules.default` and hand
      # it that one path, e.g.
      #   services.timeline-embed.enable = true;
      #   services.caddy.virtualHosts."timeline.jamesst.one".extraConfig = ''
      #     handle /embed.svg {
      #       reverse_proxy 127.0.0.1:${toString config.services.timeline-embed.port}
      #     }
      #     handle {
      #       root * ${inputs.timeline.packages.${system}.default}
      #       file_server
      #     }
      #   '';
      #
      # On x86_64-linux `nixosModules.default` also carries `services.timeline`,
      # the public instance: duckweb answering from SQL over the public-safe
      # sources, with the lane timeline at `/`. `assets`, `app`, `garmin-public`
      # and `garmin-empty` are what it runs.
      packages = eachSystem (
        system:
        {
          default = pkgsFor.${system}.callPackage ./default.nix { };
          embed = pkgsFor.${system}.callPackage ./embed.nix { };
        }
        // onSiteSystems system (sitePackages system)
      );

      nixosModules.default =
        { lib, pkgs, ... }:
        {
          imports = [
            ./module.nix
            (import ./site-module.nix {
              self = inputs.self;
              duckweb = inputs.duckweb;
            })
          ];
          services.timeline-embed.package =
            lib.mkDefault
              inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.embed;
        };

      checks = eachSystem (
        system:
        onSiteSystems system {
          site-vm = import ./nix/vm-test.nix {
            self = inputs.self;
            pkgs = pkgsFor.${system};
            inherit system;
            duckweb = inputs.duckweb.packages.${system};
          };
          site-assets = inputs.self.packages.${system}.assets;
        }
        // {
          build = inputs.self.packages.${system}.default;
          embed = inputs.self.packages.${system}.embed;
          module =
            (inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                inputs.self.nixosModules.default
                {
                  services.timeline-embed.enable = true;
                  boot.isContainer = true;
                  system.stateVersion = "26.05";
                }
              ];
            }).config.systemd.units."timeline-embed.service".unit;
        }
      );

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.mkShell {
          packages = with pkgsFor.${system}; [
            bun
            bun2nix
            nodejs
          ];
        };
      });
    };
}
