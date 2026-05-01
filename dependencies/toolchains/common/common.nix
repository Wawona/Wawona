{ lib, pkgs }:

{
  registry = import ./registry.nix;
  getBuildSystem = entry: entry.buildSystem or "autotools";
  getSource = entry: entry.source or "github";
  fetchSource =
    entry:
    let
      source = entry.source or "github";
      sha256 = entry.sha256 or lib.fakeHash;
    in
    if source == "system" then
      null
    else if source == "gitlab-gnome" then
      (
        if lib.hasAttr "tag" entry then
          pkgs.fetchgit {
            url = "https://gitlab.gnome.org/${entry.owner}/${entry.repo}.git";
            rev = "refs/tags/${entry.tag}";
            sha256 = sha256;
          }
        else if lib.hasAttr "branch" entry then
          throw "GitLab GNOME source branch is mutable, use immutable tag or commit rev: ${entry.branch}"
        else if lib.hasAttr "rev" entry then
          pkgs.fetchFromGitLab {
            domain = "gitlab.gnome.org";
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.rev;
            sha256 = sha256;
          }
        else
          throw "GitLab GNOME source requires 'rev', 'tag', or 'branch'"
      )
    else if source == "gitlab" then
      (
        if lib.hasAttr "tag" entry then
          pkgs.fetchgit {
            url = "https://gitlab.freedesktop.org/${entry.owner}/${entry.repo}.git";
            rev = "refs/tags/${entry.tag}";
            sha256 = sha256;
          }
        else if lib.hasAttr "branch" entry then
          throw "GitLab source branch is mutable, use immutable tag or commit rev: ${entry.branch}"
        else if lib.hasAttr "rev" entry then
          pkgs.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.rev;
            sha256 = sha256;
          }
        else
          throw "GitLab source requires 'rev', 'tag', or 'branch'"
      )
    else if source == "codeberg" then
      (
        if lib.hasAttr "tag" entry then
          pkgs.fetchgit {
            url = "https://codeberg.org/${entry.owner}/${entry.repo}.git";
            rev = "refs/tags/${entry.tag}";
            sha256 = sha256;
          }
        else if lib.hasAttr "branch" entry then
          throw "Codeberg source branch is mutable, use immutable tag or commit rev: ${entry.branch}"
        else if lib.hasAttr "rev" entry then
          pkgs.fetchgit {
            url = "https://codeberg.org/${entry.owner}/${entry.repo}.git";
            rev = entry.rev;
            sha256 = sha256;
          }
        else
          throw "Codeberg source requires 'rev', 'tag', or 'branch'"
      )
    else
      (
        if lib.hasAttr "tag" entry then
          pkgs.fetchFromGitHub {
            owner = entry.owner;
            repo = entry.repo;
            rev = entry.tag;
            sha256 = sha256;
          }
        else if lib.hasAttr "rev" entry then
          if entry.rev == "master" || entry.rev == "main" || entry.rev == "HEAD" then
            throw "GitHub source rev must be immutable (tag or commit SHA), not branch name: ${entry.rev}"
          else
            pkgs.fetchFromGitHub {
              owner = entry.owner;
              repo = entry.repo;
              rev = entry.rev;
              sha256 = sha256;
            }
        else
          throw "GitHub source requires either 'rev' or 'tag'"
      );
}
