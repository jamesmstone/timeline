{
  description = "James Stone's timeline — timeline.jamesst.one";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";

    # Keep in step with the bun2nix that generated bun.nix.
    bun2nix.url = "github:nix-community/bun2nix?tag=2.1.2";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";
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
      packages = eachSystem (system: {
        default = pkgsFor.${system}.callPackage ./default.nix { };
        embed = pkgsFor.${system}.callPackage ./embed.nix { };
      });

      nixosModules.default =
        { lib, pkgs, ... }:
        {
          imports = [ ./module.nix ];
          services.timeline-embed.package =
            lib.mkDefault
              inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.embed;
        };

      checks = eachSystem (system: {
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
      });

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
