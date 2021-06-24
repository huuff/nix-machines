   { config, pkgs, ... }:
   let release = "nixos-21.05";
   in {
     imports = [
       (builtins.fetchTarball {
         url = "https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/archive/${release}/nixos-mailserver-${release}.tar.gz";
         # This hash needs to be updated
         sha256 = "1fwhb7a5v9c98nzhf3dyqf3a5ianqh7k50zizj8v5nmj3blxw4pi";
       })
     ];

     mailserver = {
       enable = true;
       fqdn = "mail.example.com";
       domains = [ "example.com" "example2.com" ];
       loginAccounts = {
           "user1@example.com" = {
               # nix run nixpkgs.apacheHttpd -c htpasswd -nbB "" "super secret password" | cut -d: -f2 > /hashed/password/file/location
               hashedPassword = "$2y$05$uwZ.DVftxvA3IMjXCzGYq..XW.mXI0vLqIuh9exiKiu20hIB7lefq";

               aliases = [
                   "info@example.com"
                   "postmaster@example.com"
                   "postmaster@example2.com"
               ];
           };

           "user2@example.com" = {
              hashedPasswordFile = ./passy;
           };
       };
     };

     services.roundcube = {
        enable = true;
        hostName = "localhost";
     };

     #security.acme.email = "info@example.com";
     #security.acme.acceptTerms = true;

     networking.firewall = {
      allowedTCPPorts = [ 80 ];
     };

     services.nginx = {
        statusPage = true;
        logError = "syslog:server=localhost debug";
        virtualHosts.localhost.forceSSL = false;
        virtualHosts.localhost.enableACME = false;
      };
   }

