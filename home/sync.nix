# Your work, synced both ways with your Mac by Syncthing: the folders listed
# below, not your whole home (caches, Steam and per-machine config stay put).
# The GUI is at http://127.0.0.1:8384.
{ ... }:
let
  # .stignore never syncs, so each side only includes the shared
  # .stglobalignore that lives in (and syncs with) the folder.
  includeShared = "#include .stglobalignore\n";
in
{
  services.syncthing = {
    enable = true;
    # Devices and folders added from the GUI are kept, so pairing the Mac there
    # works before it's listed here.
    overrideDevices = false;
    overrideFolders = false;
    settings = {
      devices = {
        mac = {
          id = "DK66KBP-RFQNIO7-C3XRRSZ-UO6OV4V-FVI5ELA-PCETMXJ-3GH3NCD-D3RPMA4";
          addresses = [ "dynamic" ];
        };
      };
      # Same folder ID on both machines; the path can differ.
      folders = {
        projects = {
          label = "Projects";
          path = "~/Projects";
          devices = [ "mac" ];
        };
        # The Obsidian vault, at ~/Documents/Obsidian Vault on the Mac.
        notes = {
          label = "Notes";
          path = "~/Notes";
          devices = [ "mac" ];
        };
      };
      options.urAccepted = -1; # no usage reporting
    };
  };

  home.file."Projects/.stignore".text = includeShared;
  home.file."Notes/.stignore".text = includeShared;
}
