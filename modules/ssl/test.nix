{ pkgs, testingLib, ... }:
let
  machine1 = {
    nginxPath = "/var/www";
  };
  certPath = "/etc/ssl/certs/test.pem";
  keyPath = "/etc/ssl/private/test.pem";
in
  pkgs.nixosTest {
    name = "mk-ssl-module";

    nodes = {
      # Machine with autogenerated cert and nginx
      machine1 = { pkgs, ... }: {
        imports = [ 
          (import ./default.nix "test") 
          (import ../../lib/mk-init-module.nix "test")
        ];

        machines.test.ssl = {
          enable = true;
          sslOnly = true;
          user = "nginx";
        };

        system.activationScripts.createTestContent.text = ''
          mkdir -p ${machine1.nginxPath}
          echo "<h1>Hello World</h1>" >> ${machine1.nginxPath}/index.html
        '';

        services.nginx = {
          enable = true;

          virtualHosts.test = {
            root = machine1.nginxPath;
            locations."/".extraConfig = ''
              index index.html;
            '';
          };
        };
      };

      # Machine with cert provided by the client
      machine2 = { pkgs, ... }: {
        imports = [ 
          (import ./default.nix "test") 
          (import ../../lib/mk-init-module.nix "test")
        ];

        machines.test.ssl = {
          enable = true;
          autoGenerate = false;
          certificate = ./test_cert.pem;
          key = ./test_key.pem;
        };
      };
    };


    testScript = ''
      ${ testingLib }

      machine1.wait_for_unit("multi-user.target")
      machine2.wait_for_unit("multi-user.target")

      with subtest("unit is active"):
        machine1.succeed("systemctl is-active --quiet setup-test-cert")

      with subtest("certificate exists"):
        machine1.succeed("[ -e ${certPath} ]")
        machine1.succeed("[ -e ${keyPath} ]")

      with subtest("can access nginx with https"):
        machine1.succeed("curl -k https://localhost")

      with subtest("cannot access nginx without https"):
        machine1.outputs("curl -s -o /dev/null -w '%{http_code}' http://localhost", "301")

      with subtest("unit is not started if the certificate exists"):
        machine1.systemctl("restart setup-test-cert")
        machine1.fail("systemctl is-active --quiet setup-test-cert")

      with subtest("the certificate is the provided"):
        machine2.succeed('[ "$(sha256sum ${certPath} | cut -d\" \" -f1)" == "7e2725b2629372643539fd5c29d2607b19960ec2eb590322517439f0e31c7cd1" ]')
        machine2.succeed('[ "$(sha256sum ${keyPath} | cut -d\" \" -f1)" == "c0443356ff437e14773e43a20713f5e41efc27bbe54325fa83cca6402eee201a" ]')
    '';
  }

