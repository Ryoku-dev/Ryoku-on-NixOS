{ config, lib, options, ... }:

let
  hasHomeManager =
    lib.hasAttrByPath [ "home-manager" "users" ] options;

  homeManagerUsers =
    if hasHomeManager
    then config.home-manager.users
    else { };

  normalizeTarget = target:
    let
      withoutHome = lib.removePrefix "~/" (toString target);
      withoutDot = lib.removePrefix "./" withoutHome;
    in
    withoutDot;

  homeTargets = userConfig:
    let
      files = lib.attrByPath [ "home" "file" ] { } userConfig;
    in
    lib.concatLists (
      lib.mapAttrsToList
        (name: file:
          let
            explicit =
              if builtins.isAttrs file && file ? target && file.target != null
              then [ (normalizeTarget file.target) ]
              else [ ];
          in
          [ (normalizeTarget name) ] ++ explicit
        )
        files
    );

  xdgTargets = userConfig:
    let
      files = lib.attrByPath [ "xdg" "configFile" ] { } userConfig;
    in
    lib.concatLists (
      lib.mapAttrsToList
        (name: file:
          let
            keyTarget = ".config/${normalizeTarget name}";
            explicit =
              if builtins.isAttrs file && file ? target && file.target != null
              then
                let
                  target = normalizeTarget file.target;
                in
                [ target ".config/${target}" ]
              else [ ];
          in
          [ keyTarget ] ++ explicit
        )
        files
    );

  isRyokuRuntimeTarget = target:
    let
      normalized = normalizeTarget target;
      inRyokuConfig =
        normalized == ".config/ryoku"
        || lib.hasPrefix ".config/ryoku/" normalized;
      inUserEdits =
        normalized == ".config/ryoku/user_edits"
        || lib.hasPrefix ".config/ryoku/user_edits/" normalized;
    in
    inRyokuConfig && !inUserEdits;

  conflicts =
    lib.concatMap
      (user:
        map
          (target: "${user}: ~/${target}")
          (lib.unique (
            lib.filter
              isRyokuRuntimeTarget
              (homeTargets homeManagerUsers.${user} ++ xdgTargets homeManagerUsers.${user})
          ))
      )
      (builtins.attrNames homeManagerUsers);

in
{
  config = lib.mkIf config.programs.ryoku.enable {
    assertions = [
      {
        assertion = conflicts == [ ];
        message = ''
          Home Manager must not manage Ryoku's mutable runtime state directly.
          Conflicting paths:
          ${lib.concatMapStringsSep "\n" (path: "  - ${path}") conflicts}

          Ryoku Hub and the Ryoku CLI own ~/.config/ryoku runtime state and must
          be able to update those files in place. Remove the conflicting Home
          Manager declarations. Declarative Ryoku overrides belong under
          ~/.config/ryoku/user_edits/ instead.
        '';
      }
    ];
  };
}
