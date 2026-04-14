{
  buildModule,
  ...
}:

{
  # visionOS currently shares Apple-native dependency recipes.
  # Keep this entry point explicit so visionOS-specific overrides can land
  # without changing callers.
  buildForVisionOS = name: entry: buildModule.buildForIOS name entry;
}
