let
  rootPoolName = "rpool";
  dataPath = "/srv";

  firmwarePartition = {
    size = "1024M";
    label = "FIRMWARE";
    priority = 1;

    type = "0700"; # Microsoft basic data
    attributes = [
      0 # Required Partition
    ];

    content = {
      mountpoint = "/boot/firmware";
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

  espPartition = {
    label = "ESP";
    size = "1024M";
    type = "EF00"; # EFI System Partition (ESP)
    attributes = [
      2 # Legacy BIOS Bootable, for U-Boot to find extlinux config
    ];

    content = {
      type = "filesystem";
      format = "vfat";
      mountpoint = "/boot";
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
  ### DISKS ###
  disko.devices = {
    disk.nvme0 = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          FIRMWARE = firmwarePartition;
          ESP = espPartition;
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
          ashift = "12"; # TODO: check
          autotrim = "on";
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

        datasets = {
          system = {
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
              copies = "2";
            };
          };

          "system/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
          };
          "system/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              atime = "off";
              canmount = "on";
              mountpoint = "legacy";
              reservation = "128M";
            };
          };

          "safe/srv" = {
            type = "zfs_fs";
            mountpoint = dataPath;
            options = {
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "true";
            };
          };
        };
      };
    };
  };

  ### FILESYSTEM ###
  networking.hostId = "9561de03";
  boot.supportedFilesystems = [ "zfs" ];
  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };
  fileSystems = {
    ${dataPath}.neededForBoot = true;
  };
}
