{
  inputs = {
    systems.url = "github:nix-systems/x86_64-linux";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    ocaml-flambda = { url = "github:ocaml-flambda/flambda-backend/4.14.1-13"; flake = false; };
    opam-default = { url = "github:ocaml/opam-repository"; flake = false; };
    opam-beta = { url = "github:ocaml/ocaml-beta-repository"; flake = false; };
    opam-jane = { url = "github:janestreet/opam-repository"; flake = false; };
    opam-jane-external = { url = "github:janestreet/opam-repository/external-packages"; flake = false; };
    opam-dune-universe = { url = "github:dune-universe/opam-overlays"; flake = false; };
  };
  outputs = { self, flake-utils, opam-nix, nixpkgs, ... }@inputs:
    let
      main-overlay = final: prev: {
        ocaml = final.ocamlPackages.ocaml;
        ocamlPackages_old = prev.ocamlPackages;
        ocamlPackages = prev.ocamlPackages.overrideScope' (ofinal: oprev: {
          ocaml = prev.stdenv.mkDerivation
            {
              name = "ocaml";
              version = "4.14.1-jst12";
              src = inputs.ocaml-flambda;
              strictDeps = true;
              nativeBuildInputs = with prev; [ which rsync autoreconfHook automake final.ocamlPackages_old.ocaml final.ocamlPackages_old.dune_3 ];
              buildInputs = with prev; [ ncurses ];
              propagatedBuildInputs = with prev; [ libunwind ];
              prefixKey = "-prefix ";
              configureFlags = [ "--enable-middle-end=closure" "--enable-legacy-library-layout" ];
              postBuild = ''
                mkdir -p $out/include
                ln -sv $out/lib/ocaml/caml $out/include/caml
              '';
              buildTargets = ["compiler" ];
              installTargets = [ "install"  ];
              passthru = {
                nativeCompilers = true;
              };
              meta = oprev.ocaml.meta;
            };
        });
      };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; overlays = [ main-overlay ]; }; # nixpkgs.legacyPackages.${system};
        on = opam-nix.lib.${system};
        localPackagesQuery = builtins.mapAttrs (_: pkgs.lib.last)
          (on.listRepo (on.makeOpamRepo ./.));
        devPackagesQuery = {
          # You can add "development" packages here. They will get added to the devShell automatically.
          ocaml-lsp-server = "*";
          ocamlformat = "*";
        };
        query = devPackagesQuery // {
          ## You can force versions of certain packages here, e.g:
          ## - force the ocaml compiler to be taken from opam-repository:
          # ocaml-base-compiler = "*";
          ocaml-base-compiler = "4.14.1";
          ## - or force the compiler to be taken from nixpkgs and be a certain version:
          # ocaml-system = "4.14.1";
          ## - or force ocamlfind to be a certain version:
          # ocamlfind = "1.9.2";
          # ocaml-flambda = "*";
        };
        scope = on.buildOpamProject'
          {
            repos = with inputs; [
              opam-default
              # ./opam-repository
              # opam-beta
              # opam-jane
              # opam-jane-external
              opam-dune-universe
            ];
          } ./.
          query;
        overlay = final: prev:
          {
            ocaml-base-compiler = prev.ocaml-base-compiler.overrideAttrs (oa: { nativeBuildInputs = oa.nativeBuildInputs ++ (with pkgs; [ autoconf libtool which rsync automake dune_3 ocaml ]); });
          };
        scope' = scope.overrideScope' overlay;
        # Packages from devPackagesQuery
        devPackages = builtins.attrValues
          (pkgs.lib.getAttrs (builtins.attrNames devPackagesQuery) scope');
        # Packages in this workspace
        packages =
          pkgs.lib.getAttrs (builtins.attrNames localPackagesQuery) scope';
      in
      {
        legacyPackages = scope';

        packages = packages // {
          ocaml = pkgs.ocaml;
          ocamlPackages = pkgs.ocamlPackages;
        };
        overlay = [
          (final: prev:
            { })
        ];
        ## If you want to have a "default" package which will be built with just `nix build`, do this instead of `inherit packages;`:
        # packages = packages // { default = packages.<your default package>; };

        devShells.default = pkgs.mkShell {
          inputsFrom = builtins.attrValues packages;
          buildInputs = devPackages ++ [
            # You can add packages from nixpkgs here
          ];
        };
      });
}
