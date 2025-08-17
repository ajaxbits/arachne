{
  description = ''
    Arachne configuration (Raspberry Pi 5)
  '';

  nixConfig = {
    extra-substituters = [
      "https://cache.garnix.io"
      "https://cache.lix.systems"
      "https://nix-community.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://numtide.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      # the fork is needed for partition attributes support
      url = "github:nix-community/disko?ref=pull/1069/merge"; # TODO: go back to mainline whenever possible
      # url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    agenix = {
      url = "https://flakehub.com/f/ryantm/agenix/0.14.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
    };

    centralConfig = {
      url = "github:ajaxbits/config";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      agenix,
      disko,
      impermanence,
      lix-module,
      nixos-anywhere,
      nixos-raspberrypi,
      ...
    }@inputs:
    let
      allSystems = nixpkgs.lib.systems.flakeExposed;
      forSystems = systems: f: nixpkgs.lib.genAttrs systems f;

      user = "admin";
    in
    {

      devShells = forSystems allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              nixpkgs-fmt
              nix-output-monitor
              nixos-anywhere.packages.${system}.default
            ];
          };
        }
      );

      nixosConfigurations.arachne = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs // {
          inherit user;
        };
        modules = [
          agenix.nixosModules.age
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
          lix-module.nixosModules.default

          "${self}/configuration.nix"
        ];
      };

    };
}
