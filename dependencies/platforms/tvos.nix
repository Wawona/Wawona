{
  buildModule,
  ...
}:

{
  # tvOS keeps dedicated entrypoint; shared recipes may still be reused.
  buildForTVOS = name: entry: buildModule.buildForIOS name entry;
}
