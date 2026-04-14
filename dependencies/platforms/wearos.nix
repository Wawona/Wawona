{
  buildModule,
  ...
}:

{
  # WearOS currently shares Android-native dependency recipes.
  # Keep this entry point explicit so WearOS-specific overrides can land
  # without changing callers.
  buildForWearOS = name: entry: buildModule.buildForAndroid name entry;
}
