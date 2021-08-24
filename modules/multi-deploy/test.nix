{ pkgs, ... }:
pkgs.nixosTest {
  name = "multi-deploy";
  
  machine = { pkgs, config, lib, ... }:
  with lib;
  {
    imports = [
      ../../machines/osticket
      ../../machines/wallabag
      ../../machines/neuron
    ];

    # TODO: Automatize this
    services.mysql.package = mkForce pkgs.mariadb;

    virtualisation = {
      memorySize = "2048M";
      diskSize = 5 * 1024;
    };

    machines = {
      osticket = {
        enable = true;

        database = {
          authenticationMethod = "password";
          passwordFile = pkgs.writeText "dbpass" "dbpass";
        };

        site = {
          email = "test@example.org";
        };

        admin = {
          username = "root";
          firstName = "Name";
          lastName = "LastName";
          email = "test@test.com";
          passwordFile = pkgs.writeText "pass" "pass";
        };

        installation.group = "nginx";
      };

      wallabag = {
        enable = true;

        installation.group = "nginx";
      };

      neuron = {
        enable = true;
        repository = "https://github.com/srid/alien-psychology.git";

        installation.group = "nginx";
      };
    };

    services.nginx.user = mkForce "nginx";
  };

  testScript = ''
    ${ builtins.readFile ../../lib/testing-lib.py }

    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl is-active --quiet finish-wallabag-initialization")
    machine.succeed("systemctl is-active --quiet finish-neuron-initialization")
    machine.succeed("systemctl is-active --quiet finish-osticket-initialization")
  '';
}
