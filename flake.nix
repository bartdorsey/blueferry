{
  description = "BlueFerry — iPhone messages, notifications, and contacts on Linux over Bluetooth";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forEachSystem (system: {
        default = self.packages.${system}.blueferry;
        blueferry = (pkgsFor system).callPackage ./nix/package.nix { };
      });

      devShells = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              (pkgs.python3.withPackages (
                ps: with ps; [
                  cryptography
                  textual
                  typer
                  dbus-python
                  pygobject3
                  bandit
                  coverage
                  hypothesis
                  mypy
                  pytest
                  ruff
                ]
              ))
              pkgs.gtk4
              pkgs.libadwaita
              pkgs.libsecret
              pkgs.gobject-introspection
              pkgs.wrapGAppsHook4
              pkgs.dbus
              pkgs.bluez
              pkgs.polkit
              pkgs.desktop-file-utils
              pkgs.appstream
            ];
          };
        }
      );

      nixosModules = {
        default = self.nixosModules.blueferry;
        blueferry = import ./nix/module.nix { inherit self; };
      };

      overlays.default = final: _prev: {
        blueferry = final.callPackage ./nix/package.nix { };
      };
    };
}
