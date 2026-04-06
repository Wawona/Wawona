{
  stdenv,
  lib,
  composeXcodeWrapper,
}:
{
  name,
  app ? null,
  bundleId ? null,
  ...
}@args:

assert app != null -> bundleId != null;

let
  xcodewrapperArgs = builtins.intersectAttrs (composeXcodeWrapper.__functionArgs or (builtins.functionArgs composeXcodeWrapper)) args;
  xcodewrapper = composeXcodeWrapper xcodewrapperArgs;
in
stdenv.mkDerivation {
  name = lib.replaceStrings [ " " ] [ "" ] name;
  buildCommand = ''
    mkdir -p $out/bin
    cat > $out/bin/run-test-simulator << "EOF"
    #! ${stdenv.shell} -e

    if [ "$1" = "" ]
    then
        xcrun simctl list
        echo "Please provide a UDID of a simulator:"
        read udid
    else
        udid="$1"
    fi

    open -a "$(readlink "${xcodewrapper}/bin/Simulator")" --args -CurrentDeviceUDID $udid

    ${lib.optionalString (app != null) ''
      appTmpDir=$(mktemp -d -t appTmpDir)
      cp -r "$(echo ${app}/*.app)" "$appTmpDir"
      chmod -R 755 "$(echo $appTmpDir/*.app)"

      echo "Press enter when the simulator is started..."
      read

      xcrun simctl install "$udid" "$(echo $appTmpDir/*.app)"
      rm -Rf $appTmpDir
      xcrun simctl launch $udid "${bundleId}"
    ''}
    EOF

    chmod +x $out/bin/run-test-simulator
  '';
}
