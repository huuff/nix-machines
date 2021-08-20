name:
{ lib, config, ... }:
with lib;
let
  cfg = config.machines.${name};

  lockPath = "/etc/inits/${name}"; # Created when the initialization is finished

  initModule = with types; submodule {
    options = {
      name = mkOption {
        type = str;
        description = "Name of the systemd unit";
      };

      description = mkOption {
        type = str;
        description = "Description of the unit";
      };

      path = mkOption {
        type = listOf package;
        default = [];
        description = "Packages to add to the path of the unit";
      };

      extraDeps = mkOption {
        type = listOf str;
        default = [];
        description = "Services that are also dependencies of the unit";
      };

      user = mkOption {
        type = str;
        default = if (builtins.hasAttr "installation" cfg) then cfg.installation.user else "root";
        description = "User that will run the unit";
      };

      script = mkOption {
        type = str;
        description = "Script that will be run";
      };
    };
  };

  initModuleToUnit = initModule: nameValuePair initModule.name {
    script = initModule.script;
    description = initModule.description;
    path = initModule.path;

    serviceConfig = {
      User = initModule.user;
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = mkIf (hasAttr "installation" cfg) cfg.installation.path;
    };

    unitConfig = {
      After = initModule.extraDeps;
      BindsTo = initModule.extraDeps;
    };
  };

  after = first: second: recursiveUpdate second {
    value.unitConfig = {
      After = [ "${first.name}.service" ] ++ second.value.unitConfig.After;
      BindsTo = [ "${first.name}.service" ] ++ second.value.unitConfig.BindsTo;
    };
  };

  # This creates a unit that is required by all others, running only if the "lock" does not exist
  # Therefore, if the "lock" exists (which means the initialization is complete) then nothing will run
  firstUnit = {
    name = "start-${name}-initialization";

    value = {
      description = "Start the provisioning of ${name}";

      script = "echo 'Start provisioning ${name}'";

      serviceConfig = {
        User = "root";
        Type = "oneshot";
        RemainAfterExit = true;
      };

      unitConfig = {
        ConditionPathExists = "!${lockPath}"; 
      };

    };
  };

  # This creates a new unit that satisfies the following:
  # * Is after and requires all units in init.
  # * Is wanted by multi-user target, so it will be auto-started and propagate to all others.
  # * It creates a file that will signify the end of the initialization (the "lock")
  lastUnit = {
    name = "finish-${name}-initialization";

    value = {
      description = "Finish the provisioning of ${name}";
      script = ''
        mkdir -p /etc/inits
        touch ${lockPath}
        chmod 600 ${lockPath}
      '';

      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "root";
        Type = "oneshot";
        RemainAfterExit = true;
      };

      # Just so after function works
      unitConfig = {
        After = [];
        BindsTo = [];
      };
    };
  };

  # Aux function for orderUnits
  orderUnitsRec = current: alreadyOrdered: unorderedYet: 
  if (length unorderedYet) == 0
  then
    alreadyOrdered ++ [ (after current lastUnit) ]
  else let 
    next = head unorderedYet;
    nextAfterCurrent = after current next;
    rest = tail unorderedYet;
  in
    orderUnitsRec next (alreadyOrdered ++ [nextAfterCurrent]) rest;

  # Orders units (sets after and binds to for each one to be after the other), adds first and last units
  orderUnits = units: orderUnitsRec (firstUnit) [firstUnit] (units);

in  
  {
    options = {
      machines.${name}.initialization = mkOption {
        type = types.listOf initModule;
        default = [];
        description = "Each of the scripts to run for provisioning, in the required order";
      };
    };

    config = {
      systemd.services = 
      let
        unorderedUnits = map initModuleToUnit cfg.initialization;
        orderedUnits = orderUnits unorderedUnits;
      in (listToAttrs orderedUnits);
    };
  }
