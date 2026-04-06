args @ { lib, pkgs, TEAM_ID ? null, ... }:

let
  iosXcodeenv = import ../toolchains/ios-xcodeenv.nix args;
in
iosXcodeenv
// {
  xcodeWrapper = iosXcodeenv.xcodeWrapperCommand;
  getXcodePath = iosXcodeenv.findXcodeScript;
}
