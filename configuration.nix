{
  centralConfig,
  config,
  nixos-raspberrypi,
  pkgs,
  lib,
  ...
}:
let
  hostName = "arachne";
in
{
  imports = with nixos-raspberrypi.nixosModules; [
    ./disks.nix
    {
      _module.args = { inherit hostName; };
    }

    ./configtxt.nix
    raspberry-pi-5.base
    raspberry-pi-5.bluetooth

    ./docker.nix
    ./stub.nix
    "${centralConfig}/common/users.nix"
    "${centralConfig}/common/ssh.nix"
    "${centralConfig}/common/nix.nix"
    "${centralConfig}/common/upgrade-diff.nix"

    "${centralConfig}/components/cd"
    "${centralConfig}/components/caddy"
    "${centralConfig}/components/bookmarks"
    (import "${centralConfig}/components/tailscale" {
      inherit config lib;
      pkgsUnstable = pkgs;
    })
  ];

  services.scrutiny = {
    enable = true;
    openFirewall = true;
    settings.web.listen.port = 6464;
  };

  components = {
    caddy = {
      enable = true;
      cloudflare.enable = true;
    };
    cd = {
      enable = true;
      repo = "ajaxbits/arachne";
    };
    bookmarks.enable = true;
    tailscale = {
      enable = true;
      initialAuthKey = "tskey-auth-k4o2kmWUBn11CNTRL-cyLocuNQTfS93v1Ay8vuiSZBMBeEtEU4";
      tags = [
        "ajax"
        "homelab"
        "nixos"
      ];
      advertiseExitNode = true;
      advertiseRoutes = [ "172.22.0.0/15" ];
    };
  };

  # Time & hostname
  time.timeZone = "America/Chicago";

  networking = {
    inherit hostName;
    domain = "ajax.casa";

    useNetworkd = true;
    firewall.enable = false;
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
    du-dust
    fd
    hck
    git
    jq
    neovim
    nix-output-monitor
    rclone
    ripgrep
    rsync
    sd
    tmux
    unzip
    wget
  ];

  # SSH + sudo + polkit
  security = {
    polkit.enable = true;
    sudo.enable = false;
    doas.enable = true;
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
