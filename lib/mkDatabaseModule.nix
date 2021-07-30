name:
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.${name};
  myLib = import ./default.nix { inherit config; };
in
  {
    options = with types; {
      services.${name} = {
        database = {
          host = mkOption {
            type = str;
            default = "localhost";
            description = "Host location of the database";
          };

          name = mkOption {
            type = str;
            default = name;
            description = "Name of the database";
          };

          user = mkOption {
            type = str;
            default = name;
            description = "Name of the database user";
          };

          passwordFile = mkOption {
            type = oneOf [ str path ];
            description = "Password of the database user";
          };

          prefix = mkOption {
            type = str;
            default = "${name}_";
            description = "Prefix to put on all tables of the database";
          };
        };
      };
    };

    config = {
      services.mysql = {
        enable = true;
        package = pkgs.mariadb;
      };

      systemd.services = {
        "setup-${name}-db" = {
          description = "Create ${cfg.database.name} and give ${cfg.database.user} permissions to it";

          script = myLib.db.execDDL ''
            CREATE DATABASE ${cfg.database.name};
            CREATE USER '${cfg.database.user}'@${cfg.database.host} IDENTIFIED BY '${myLib.catPasswordFile cfg.database.passwordFile}';
            GRANT ALL PRIVILEGES ON ${cfg.database.name}.* TO '${cfg.database.user}'@${cfg.database.host};
          ''; 

          unitConfig = {
            After = [ "mysql.service" ];
            Requires = [ "mysql.service" ];
          };

          serviceConfig = {
            User = "root";
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
      };
    };
  }
