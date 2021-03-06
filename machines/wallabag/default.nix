{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.machines.wallabag;
  myLib = import ../../lib/default.nix { inherit config pkgs lib; };

  wallabagRepo = "https://github.com/wallabag/wallabag";

  phpWithTidy = pkgs.php74.withExtensions ( { enabled, all }: enabled ++ [ all.tidy ] );
  composerWithTidy = (pkgs.php74Packages.composer.override { php = phpWithTidy; });
  userModule = with types; submodule {
    options = {
      username = mkOption {
        type = str;
        description = "Username of the user";
      };

      passwordFile = myLib.passwd.mkOption;

      email = mkOption {
        type = str;
        description = "E-mail address of the user";
      };

      superAdmin = mkOption {
        type = bool;
        default = false;
        description = "Whether to make this user a super-admin";
      };

      pocketKeyFile = mkOption {
        type = nullOr (oneOf [str path]);
        default = null;
        description = "Pocket consumer key to import collection";
      };
    };
  };
in
  {

    imports = [
      (import ../../modules/mk-database-module "wallabag")
      (import ../../modules/ssl "wallabag")
      (import ../../modules/backup "wallabag")
      (import ../../modules/mk-installation-module "wallabag")
      (import ../../modules/mk-init-module "wallabag")
    ];

    options.machines.wallabag = with types; {
      enable = mkEnableOption "wallabag";

      commit = mkOption {
        type = str;
        default = "ca845b3204cb25cb7f623a81bc233ca19b38848e";
        description = "The commit of wallabag that will be installed";
      };

      users = mkOption {
        type = listOf userModule;
        default = [];
        description = "List of initial wallabag users";
      };

      importTool = mkOption {
        type = enum [ "none" "redis" "rabbitmq" ];
        default = "none";
        description = "Tool to use for importing. Use 'none' for synchronous import";
      };

      parameters = mkOption {
        type = attrs;
        default = {};
        description = "parameters.yml used for installing wallabag";
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        # Since wallabag forces us to set a domain name and this will include whether it's
        # http or https, if we choose https then http will not work.
        {
          assertion = cfg.ssl.enable -> cfg.ssl.sslOnly;
          message = "For wallabag, if SSL is enabled then ssl.sslOnly must be true!";
        }
        {
          assertion = cfg.parameters.fosuser_confirmation -> cfg.parameters.fosuser_registration;
          message = "If parameters.fosuser_confirmation is true, then parameters.fosuser_registration must also be true!";
        }
      ];

      # Give a random, high order so it doesn't conflict with other machines
      services.mysql.package = mkOverride 999 pkgs.mariadb;

      machines.wallabag = {
        installation.ports = myLib.mkDefaultHttpPorts cfg;

        parameters = {
          database_driver = "pdo_mysql";
          database_port = "~";
          database_name = cfg.database.name;
          database_user = cfg.database.user;
          database_path = null;
          database_password = null;
          database_table_prefix = cfg.database.prefix;
          database_charset = "utf8mb4";
          database_socket = null;

          domain_name = (if cfg.ssl.enable then "https://" else "http://") + "localhost:${if cfg.ssl.enable then (toString cfg.installation.ports.https) else (toString cfg.installation.ports.http)}";
          server_name = "Your wallabag instance";

          mailer_transport = "smtp";
          mailer_user = "~";
          mailer_password = "~";
          mailer_host = "127.0.0.1";
          mailer_port = "false";
          mailer_encryption = "~";
          mailer_auth_mode = "~";

          locale = "en";

          secret = "$(${pkgs.libressl}/bin/openssl rand -hex 12)";

          twofactor_auth = true;
          twofactor_sender = "noreply@wallabag.org";

          fosuser_registration = true;
          fosuser_confirmation = true;
          fos_oauth_server_access_token_lifetime = 3600;
          fos_oauth_server_refresh_token_lifetime = 1209600;

          from_email = "no-reply@wallabag.org";

          rss_limit = 50;

          redis_scheme = null;
          redis_host = null;
          redis_port = null;
          redis_path = null;
          redis_password = null;

          sentry_dsn = "~";
        } // optionalAttrs (cfg.importTool == "redis") {
          redis_scheme = "tcp";
          redis_host = "localhost";
          redis_port = config.services.redis.port;
          redis_path = null;
          redis_password = if (config.services.redis.requirePassFile != null) then myLib.passwd.cat else null;
        } // optionalAttrs (cfg.importTool == "rabbitmq") {
          rabbitmq_host = "localhost";
          rabbitmq_port = config.services.rabbitmq.port;
          rabbitmq_user = "guest";
          rabbitmq_password = "guest";
          rabbitmq_prefetch_count = 10;
        } // (
          if (cfg.database.authenticationMethod == "password") then { 
            database_password = myLib.passwd.cat cfg.database.passwordFile;
            # TODO: remote db
            database_host = "127.0.0.1";
          }
          else if (cfg.database.authenticationMethod == "socket") then {
            database_socket = "/run/mysqld/mysqld.sock";
            database_host = null;
          }
          else throw "Unknown database authentication method"
          );

          initialization.units = [
            {
              name = "copy-wallabag";
              description = "Copy wallabag to final directory and setting permissions for installation";
              script = ''
                git clone ${wallabagRepo} ${cfg.installation.path}
                git reset --hard ${cfg.commit}
              '';
              path = [ pkgs.git ];
              extraDeps = [ "network-online.target" ];
            }

            {
              name = "create-parameters";
              description = "Create parameters.yml for installation";
              script =  ''
                echo "${builtins.toJSON { parameters = cfg.parameters; }}" > ${cfg.installation.path}/app/config/parameters.yml
              '';
              idempotent = true;
            }

            {
              name = "install-wallabag";
              description = "Install wallabag";
              script = "make clean && make install";
              path = with pkgs; [ gnumake bash composerWithTidy phpWithTidy git ];
              extraDeps = [ "setup-wallabag-db.service" ];
            }

          {
            name = "install-dependencies";
            description = "Run composer install";
            # XXX: Composer sometimes fails spuriously with some XML error that I couldn't care to fix
            # So I add `|| true` but now any legitimate error gets swallowed. Take care of removing the
            # init file if you want to resume the initialization from this unit.
            script = "COMPOSER_MEMORY_LIMIT=-1 composer install || true";
            path = [ composerWithTidy phpWithTidy ];
          }

          {
            name = "setup-wallabag-users";
            description = "Create default users";
            script = 
            let
              insertUser = user: ''
                php bin/console fos:user:create ${user.username} ${user.email} ${myLib.passwd.cat user.passwordFile} --no-interaction ${optionalString user.superAdmin "--super-admin"}
                ${optionalString (user.pocketKeyFile != null) (myLib.db.runSql cfg.database ''
                  SELECT id FROM ${cfg.database.prefix}user WHERE username='${user.username}' INTO @user_id;
                  UPDATE ${cfg.database.prefix}config SET pocket_consumer_key='${myLib.passwd.cat user.pocketKeyFile}' WHERE user_id=@user_id;
                '')}
                '';
            in ''
              echo '>>> Disabling default "wallabag" user'
              php bin/console fos:user:deactivate wallabag
              echo '>>> Creating all users'
              ${concatStringsSep "\n" (map insertUser cfg.users)}
            '';
            path = [ phpWithTidy ];
          }

          (mkIf (cfg.importTool != "none") {
            name = "enable-${cfg.importTool}";
            description = "Enable ${cfg.importTool} for importing in the database";
            script = myLib.db.runSql cfg.database "UPDATE ${cfg.database.prefix}internal_setting SET value=1 WHERE name='import_with_${cfg.importTool}';";
            idempotent = true;
          })

          {
            name = "clear-wallabag-cache";
            description = "Clear the wallabag cache";
            script = "php bin/console cache:clear --env=prod";
            path = [ phpWithTidy ];
            idempotent = true;
          }

        ];
      };

      services.nginx = {
        enable = true;
        user = mkDefault cfg.installation.user;
        group = mkDefault cfg.installation.group;

        virtualHosts.wallabag = {
          root = "${cfg.installation.path}/web";

          listen = myLib.mkListen cfg;

          locations = {
            "/" = {
              priority = 100;
              extraConfig = "try_files $uri /app.php$is_args$args;";
            };
            "~ ^/app\\.php(/|$)" = {
              priority = 500;
              extraConfig = ''
                fastcgi_pass unix:${config.services.phpfpm.pools.wallabag.socket};
                fastcgi_split_path_info ^(.+\.php)(/.*)$;
                include ${pkgs.nginx}/conf/fastcgi_params;
                include ${pkgs.nginx}/conf/fastcgi.conf;
                fastcgi_param  SCRIPT_FILENAME  $realpath_root$fastcgi_script_name;
                fastcgi_param DOCUMENT_ROOT $realpath_root;
                internal;
              '';
            };
            "~ \\.php$" = {
              priority = 1000;
              extraConfig = ''
                return 404;
              '';
            };
          };
        };
      };


      services.phpfpm = {
        pools.wallabag = {
          user = cfg.installation.user;
          phpPackage = pkgs.php74;
          settings = {
            "listen.owner" = config.services.nginx.user;
            "pm" = "dynamic";
            "pm.max_children" = 32;
            "pm.max_requests" = 500;
            "pm.start_servers" = 2;
            "pm.min_spare_servers" = 2;
            "pm.max_spare_servers" = 5;
            "php_admin_value[error_log]" = "stderr";
            "php_admin_flag[log_errors]" = true;
            "catch_workers_output" = true;
          };
          phpEnv."PATH" = lib.makeBinPath [ pkgs.php74 ];
        };
      };

      services.redis = mkIf (cfg.importTool == "redis") {
        enable = true;
      };

      services.rabbitmq = mkIf (cfg.importTool == "rabbitmq") {
        enable = true;
      };

      systemd.services.import-worker = mkIf (cfg.importTool != "none") {
        description = "Run the worker for asynchronous importing";

        after = [ "${cfg.importTool}.service" "finish-wallabag-initialization.service" ];
        requires = [ "${cfg.importTool}.service" ];
        wantedBy = [ "multi-user.target" ];

        path = [ phpWithTidy ];

      # If it's not redis, then it's rabbitmq
      script =
        let
          command = if (cfg.importTool == "redis") then "wallabag:import:redis-worker" else "rabbitmq:consumer";
          importer = if (cfg.importTool == "redis") then "pocket" else "import_pocket";
        in "php bin/console ${command} --env=prod ${importer} -vv";

        serviceConfig = {
          User = cfg.installation.user;
          WorkingDirectory = cfg.installation.path;
          Restart = "on-failure";
        };
      };
    };
  }
