{
  description = "Neuron instance with nginx";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-21.05";
    nixops.url = "github:NixOS/nixops";
    utils.url = "github:numtide/flake-utils";
    neuron.url = "github:srid/neuron";
    mydrvs.url = "github:huuff/derivations";
  };

  outputs = { self, nixpkgs, nixops, neuron, utils, mydrvs, ... }:
  {

    overlay = final: prev: {
      neuron-notes = neuron.packages.x86_64-linux.neuron;
    };

    nixopsConfigurations.default =
      let
        repo = "git@github.com:huuff/exobrain.git";
        keyPath = "/home/haf/exobrain/deploy_rsa";
      in
      {
        inherit nixpkgs;

        network.description = "Neuron";
        neuron = { config, pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlay ];
          imports = [
            (import ./neuron.nix { inherit config pkgs repo; })
            ./cachix.nix
            mydrvs.nixosModules.do-on-request 
            mydrvs.nixosModules.neuron-module
          ];

          deployment = {
            targetEnv = "libvirtd";
            libvirtd.headless = true;
            keys.deploy.keyFile = keyPath;
            keys.deploy.user = "neuron";
            keys.deploy.group = "neuron";
          };
        };
      };
    };

  }
