{ pkgs, testingLib, ... }:
let
  canonicalDomain = "example.com";
  user1Address = "user1@${canonicalDomain}";
  user2Address = "user2@${canonicalDomain}";
  installationPath = "/var/lib/postfix";
  testContent = "test content";
  testSubject = "test subject";
  mailPath = "/var/lib/vmail";
in
pkgs.nixosTest {
  name = "postfix-virtual";

  machine = { pkgs, ... }: {
    imports = [
      ../default.nix
    ];

    environment.systemPackages = with pkgs; [ mailutils ];

    machines.postfix = {
      enable = true;
      inherit canonicalDomain mailPath;

      maps.virtual_mailbox_maps.path = installationPath;

      users = [
        user1Address
        user2Address
      ];
    };

  };

  testScript = ''
    ${ testingLib }

    machine.wait_for_unit("multi-user.target")

    with subtest("unit is active"):
      machine.succeed("systemctl is-active --quiet postfix")

    with subtest("virtual mailbox map works"):
      machine.succeed("postalias -q ${user1Address} hash:${installationPath}/virtual_mailbox_maps")
      machine.succeed("postalias -q ${user2Address} hash:${installationPath}/virtual_mailbox_maps")
      # Sanity check
      machine.fail("postalias -q pepo hash:${installationPath}/virtual_mailbox_maps")

    with subtest("can send and receive email from local"):
      machine.succeed('echo "${testContent}" | mail -u ${user1Address} -s "${testSubject}" ${user2Address}')
      machine.wait_until_succeeds('echo p | mail -f ${mailPath}/${user2Address}')
      machine.output_contains('echo p | mail -f ${mailPath}/${user2Address}/', "To: <${user2Address}>")
      machine.output_contains('echo p | mail -f ${mailPath}/${user2Address}/', "Subject: ${testSubject}")
      machine.output_contains('echo p | mail -f ${mailPath}/${user2Address}/', "${testContent}")

  '';
}
