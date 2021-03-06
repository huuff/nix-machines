{ name, repository, borgLib, ... }:
{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.machines.${name}.backup;
  dbCfg = config.machines.${name}.database;

  myLib = import ../../lib/default.nix { inherit config pkgs lib; };
  borgLib = import ./borg-lib.nix { inherit lib myLib; };
in
{
  options = with types; {
    machines.${name}.backup.database = {
      enable = mkEnableOption "database backup";

      repository = mkOption {
        type = repository;
        default = {};
        description = "Options for the borg repository where the database backup will be stored";
      };
    };
  };

  config = mkIf cfg.database.enable {

    assertions = [
      {
        assertion = config.machines.${name} ? database;
        message = "Can't enable database backup without enabling database!";
      }
    ];

    machines.${name}.initialization.units = (mkAfter [
        (mkIf cfg.restore {
          name = "restore-${name}-database-backup";
          description = "Restore the latest ${name} database backup";
          path = with pkgs; [ borgbackup openssh ];
          script = let repo = cfg.database.repository; in
          ''
            ${borgLib.setEnv repo}
            if ${borgLib.repoNotEmpty repo}; then
              latest_archive=${borgLib.latestArchive repo}

              borg extract --stdout ${borgLib.buildPath repo}::$latest_archive | ${config.services.mysql.package}/bin/mysql
            fi
          '';
          user = "root";
        })
      ]);

      systemd = {
        tmpfiles.rules = mkIf (cfg.database.repository.localPath != null)
          [ "d ${cfg.database.repository.localPath} 700 ${cfg.user} ${cfg.user} - -" ];

        timers."backup-${name}-database" = {
            wantedBy = [ "timers.target" ];

            partOf = [ "backup-${name}-database.service" ];

            timerConfig.OnCalendar = cfg.frequency;
          };
        
          services."backup-${name}-database" = {
            description = "Make a backup of the ${name} database";

            path = with pkgs; [ config.services.mysql.package borgbackup openssh ];

            script = let repo = cfg.database.repository; in
            ''
              ${borgLib.setEnv repo}
              mysqldump --order-by-primary ${myLib.db.authentication dbCfg} --databases ${dbCfg.name} --add-drop-database | borg create ${borgLib.compressionArg cfg} ${borgLib.buildPath repo}::{now} -
            '';

            serviceConfig = {
              Type = "oneshot";
              User = cfg.user;
            };
          };
        };

  };
}
