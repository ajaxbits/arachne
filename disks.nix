{ config, lib, ... }:

let
  rootPoolName = "rpool";
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

  networking.hostId = "0bd1a88c";
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  fileSystems = {
    "/var/log".neededForBoot = true;
    "/persistent".neededForBoot = true;
  };

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
              pool = rootPoolName; # zroot
            };
          };

        };
      };
    }; # nvme0

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
          # "com.sun:auto-snapshot" = "false";
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

        postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^${rootPoolName}@blank$' || zfs snapshot ${rootPoolName}@blank";

        datasets = {
          local = {
            type = "zfs_fs";
            options.mountpoint = "none";
          };
          safe = {
            type = "zfs_fs";
            options = {
              copies = "2";
              mountpoint = "none";
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
              zfs snapshot rpool/local/root@blank
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
          "local/log" = {
            type = "zfs_fs";
            mountpoint = "/var/log";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "true";
            };
          };

          "safe/data" = {
            type = "zfs_fs";
            mountpoint = "/data";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "true";
            };
          };
          "safe/persistent" = {
            type = "zfs_fs";
            mountpoint = "/persistent";
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "true";
            };
          };
        };
      };
    };
  };

  environment.persistence."/persistent" = {
    hideMounts = true;
    directories = [
      "/etc/ssh"
      "/var/lib/bluetooth"
      "/var/lib/fwupd"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/upower"
    ];
    files = [
      "/etc/adjtime"
      "/etc/machine-id"
      "/etc/zfs/zpool.cache"
    ];
  };
}
