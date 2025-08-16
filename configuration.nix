{
  centralConfig,
  config,
  nixos-raspberrypi,
  user,
  pkgs,
  ...
}:
let
  hostName = "arachne";
in
{
  imports = with nixos-raspberrypi.nixosModules; [
    ./configtxt.nix
    ./disks.nix
    raspberry-pi-5.base
    raspberry-pi-5.bluetooth
    "${centralConfig}/common/users.nix"
    "${centralConfig}/common/ssh.nix"
    "${centralConfig}/common/nix.nix"
    "${centralConfig}/common/upgrade-diff.nix"
    "${centralConfig}/common/fish.nix"
    "${centralConfig}/common/pkgs.nix"
  ];

  # Time & hostname
  time.timeZone = "America/Chicago";

  networking = {
    inherit hostName;
    domain = "ajax.casa";

    # Safe(ish) network defaults + iwd
    useNetworkd = true;
    firewall.allowedUDPPorts = [ 5353 ];
    wireless.enable = false;
    wireless.iwd = {
      enable = true;
      settings = {
        Network = {
          EnableIPv6 = true;
          RoutePriorityOffset = 300;
        };
        Settings.AutoConnect = true;
      };
    };
  };
  systemd.network.networks = {
    "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
    "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
  };
  systemd.services = {
    systemd-networkd.stopIfChanged = false;
    systemd-resolved.stopIfChanged = false;
  };

  # Console / udev niceties
  services.udev.extraRules = ''
    # Ignore partitions with "Required Partition" GPT partition attribute
    # On our RPis this is firmware (/boot/firmware) partition
    ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
      ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
      ENV{UDISKS_IGNORE}="1"
  '';

  # Packages
  environment.systemPackages = with pkgs; [
    neovim
    tree
  ];

  # SSH + sudo + polkit
  security = {
    polkit.enable = true;
    sudo.enable = false;
    doas.enable = true;
    security.doas.extraRules = [
      {
        users = [ user ];
        keepEnv = true;
      }
    ];

  };

  # Stateless: follow latest
  system.stateVersion = config.system.nixos.release;

  # Useful tags
  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberryPi;
    in
    [
      hostName
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];

  # tmpfs for /tmp
  boot.tmp.useTmpfs = true;
}
