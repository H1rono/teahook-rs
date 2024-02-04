# https://github.com/nix-community/fenix/blob/28dbd8b43ea328ee708f7da538c63e03d5ed93c8/default.nix#L5-L12
let
  inherit (builtins) fromJSON readFile;
in
name:
with (fromJSON (readFile ../flake.lock)).nodes.${name}.locked; {
  inherit rev;
  outPath = fetchTarball {
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    sha256 = narHash;
  };
}
