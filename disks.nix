{
  config,
  lib,
  pkgs,
  user,
  ...
}:

let
  rootPoolName = "rpool";

  dataPath = "/data";
  persistentPath = "/persist";

  firmwarePartition = lib.recursiveUpdate {
    priority = 1;

    type = "0700"; # Microsoft basic data
    attributes = [
      0 # Required Partition
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  espPartition = lib.recursiveUpdate {
    type = "EF00"; # EFI System Partition (ESP)
    attributes = [
      2 # Legacy BIOS Bootable, for U-Boot to find extlinux config
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
        "umask=0077"
      ];
    };
  };

in
{
  networking.hostId = builtins.substring 0 8 (
    builtins.hashString "sha256" config.networking.hostName
  );
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  disko.devices = {
    disk.nvme0 = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {

          FIRMWARE = firmwarePartition {
            label = "FIRMWARE";
            content.mountpoint = "/boot/firmware";
          };

          ESP = espPartition {
            label = "ESP";
            content.mountpoint = "/boot";
          };

          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = rootPoolName;
            };
          };

        };
      };
    };

    zpool = {
      ${rootPoolName} = {
        type = "zpool";

        # zpool properties
        options = {
          ashift = "12";
          autotrim = if config.services.zfs.trim.enable then "on" else "off"; # see also services.zfs.trim.enable
        };

        # zfs properties
        rootFsOptions = {
          # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/
          compression = "lz4";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          # https://rubenerd.com/forgetting-to-set-utf-normalisation-on-a-zfs-pool/
          normalization = "formD";
          dnodesize = "auto";
          mountpoint = "none";
          canmount = "off";
        };

        datasets =
          let
            diskCount = builtins.length (builtins.attrNames config.disko.devices.disk);
          in
          {
            local = {
              type = "zfs_fs";
              options.mountpoint = "none";
            };
            safe = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                # When we are mirroring, we only need one copy, but if we
                # only have one disk, let's keep safe data at 2 copies
                # to protect from bitrot
                copies = if diskCount > 1 then "2" else "1";
              };
            };

            "local/reserved" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                reservation = "5GiB";
              };
            };
            "local/root" = {
              type = "zfs_fs";
              mountpoint = "/";
              options.mountpoint = "legacy";
              postCreateHook = ''
                zfs snapshot ${rootPoolName}/local/root@blank
              '';
            };
            "local/nix" = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                atime = "off";
                canmount = "on";
                mountpoint = "legacy";
                reservation = "128M";
                "com.sun:auto-snapshot" = "true";
              };
            };

            "safe/data" = {
              type = "zfs_fs";
              mountpoint = dataPath;
              options = {
                mountpoint = "legacy";
                "com.sun:auto-snapshot" = "true";
              };
            };
            "safe/persist" = {
              type = "zfs_fs";
              mountpoint = persistentPath;
              options = {
                mountpoint = "legacy";
                "com.sun:auto-snapshot" = "true";
              };
            };
          };
      };
    };
  };

  # Actually do the rollback
  boot.initrd.systemd = {
    enable = true;
    services.initrd-rollback-root = {
      after = [ "zfs-import-${rootPoolName}.service" ];
      wantedBy = [ "initrd.target" ];
      before = [ "sysroot.mount" ];
      path = [ pkgs.zfs ];
      description = "Rollback root fs";
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = "zfs rollback -r ${rootPoolName}/local/root@blank";
    };
  };

  # Make sure boot actually happens
  fileSystems = {
    ${dataPath}.neededForBoot = true;
    ${persistentPath}.neededForBoot = true;
  };

  # Link everything with persistence
  environment = {
    persistence.${persistentPath} = {
      hideMounts = true;
      directories = [
        "/var/lib"
        "/var/log"
      ];
      files = [
        "/etc/adjtime"
        "/etc/machine-id"
        "/etc/ssh/authorized_keys.d/${user}"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
        "/etc/zfs/zpool.cache"
      ];
    };

    etc = {
      "/etc/ssh/authorized_keys.d/${user}".source = "${persistentPath}/etc/ssh/authorized_keys.d/${user}";
      "ssh/ssh_host_ed25519_key.pub".source = "${persistentPath}/etc/ssh/ssh_host_ed25519_key.pub";
      "ssh/ssh_host_ed25519_key".source = "${persistentPath}/etc/ssh/ssh_host_ed25519_key";
      "ssh/ssh_host_rsa_key.pub".source = "${persistentPath}/etc/ssh/ssh_host_rsa_key.pub";
      "ssh/ssh_host_rsa_key".source = "${persistentPath}/etc/ssh/ssh_host_rsa_key";
      "machine-id".source = "${persistentPath}/etc/machine-id";
    };
  };

  services.openssh = {
    hostKeys = [
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
      }
    ];
  };
}
