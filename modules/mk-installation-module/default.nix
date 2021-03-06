name:
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.machines.${name}.installation;
in
  {
    options = {
      machines.${name}.installation = with types; {

        user = mkOption {
          type = str;
          default = name;
          description = "User on which ${name} will run";
        };

        path = mkOption {
          type = oneOf [ path str ];
          default = "/var/lib/${name}";
          description = "Path of the installation";
        };

        group = mkOption {
          type = str;
          default = cfg.user;
          description = "Default group of the user";
        };

        ports = mkOption {
          type = attrsOf port;
          default = {};
          description = "Name of protocol to port that will be open/served by the application";
        };
      };
    };

    config = {
      networking.firewall.allowedTCPPorts = mapAttrsToList (name: value: value) cfg.ports;

      systemd.tmpfiles.rules = [ "d ${cfg.path} - ${cfg.user} ${cfg.group} - -" ];

      users = {
        users.${cfg.user} = {
          isSystemUser = mkDefault true;
          home = cfg.path;
          group = cfg.user;
          extraGroups = [ "keys" cfg.group ]; # needed for nixops, to access /run/keys
        };

        groups = mkMerge [
          { ${cfg.group} = {}; } # create the group
          (mkIf (cfg.group != cfg.user) { ${cfg.user} = {}; }) # create a group with user's name
        ];
      };
    };
  }
