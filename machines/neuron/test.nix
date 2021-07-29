{ pkgs, doOnRequest, neuronPkg, ... }:
# Test are quite expensive to set up, so I'll test everything here
let
  directory = "/home/neuron";
in
pkgs.nixosTest {
  name = "neuron";

  machine = { pkgs, ... }: {
    imports = [ (import ./default.nix { inherit doOnRequest neuronPkg; }) ];

    environment.systemPackages = with pkgs; [ git ];

    nix.useSandbox = false;
    
    services.neuron = {
      enable = true;
      repository = "https://github.com/srid/alien-psychology.git";
      refreshPort = 8999;
      inherit directory;
    };
  };

  testScript = ''
      machine.wait_for_unit("default.target")

      with subtest("units are active"):
        machine.succeed("systemctl is-active --quiet neuron")
        machine.succeed("systemctl is-active --quiet do-on-request")
        machine.succeed("systemctl is-active --quiet nginx")

      with subtest("directory is created"):
        machine.succeed("[ -d ${directory} ]")

      print("Try shell_interact")
      machine.shell_interact()
      print("End it")

      with subtest("repository was cloned"):
        machine.succeed("git -C ${directory} rev-parse")

      with subtest("neuron generates output"):
        machine.wait_until_succeeds("[ -e /home/neuron/.neuron/output/index.html ]")

      with subtest("nginx is serving the zettelkasten"):
        [status, out] = machine.execute('curl -o /dev/null -s -w "%{http_code}" localhost:80')
        print(out)

    '';
}