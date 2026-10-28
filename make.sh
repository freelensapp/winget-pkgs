#!/bin/bash

set -euo pipefail

version=$(yq -r .freelens .versions.yaml)

releaseDate=$(gh release view v"${version}" -R freelensapp/freelens --json publishedAt --jq .publishedAt | sed 's/T.*//')
releaseUrl=$(gh release view v"${version}" -R freelensapp/freelens --json url --jq .url)
installerX64Url=$(gh release view v"${version}" -R freelensapp/freelens --json assets --jq '.assets[] | select(.name == "Freelens-'"${version}"'-windows-amd64.exe").url')
installerArm64Url=$(gh release view v"${version}" -R freelensapp/freelens --json assets --jq '.assets[] | select(.name == "Freelens-'"${version}"'-windows-arm64.exe").url')
installerX64Sha256Url=$(gh release view v"${version}" -R freelensapp/freelens --json assets --jq '.assets[] | select(.name == "Freelens-'"${version}"'-windows-amd64.exe.sha256").url')
installerArm64Sha256Url=$(gh release view v"${version}" -R freelensapp/freelens --json assets --jq '.assets[] | select(.name == "Freelens-'"${version}"'-windows-arm64.exe.sha256").url')
installerX64Sha256=$(curl -sSL "${installerX64Sha256Url}" | cut -f1 -d' ' | tr '[:lower:]' '[:upper:]')
installerArm64Sha256=$(curl -sSL "${installerArm64Sha256Url}" | cut -f1 -d' ' | tr '[:lower:]' '[:upper:]')

gh release view v"${version}" -R freelensapp/freelens --json body --jq .body | tr -d '\015' | sed -z 's/\n*$//' >release-notes.tmp

# The WinGet schema allows at most 10000 characters in ReleaseNotes. Longer
# notes keep the whole lines that fit, without a heading left empty at the
# end, and end with a link to the release.
RELEASE_URL="${releaseUrl}" MAX_LENGTH=10000 perl -CSD -0777 -i -pe '
  my $more = "\n\n...\n\nFull release notes: $ENV{RELEASE_URL}";
  if (length > $ENV{MAX_LENGTH}) {
    $_ = substr($_, 0, $ENV{MAX_LENGTH} - length $more);
    s/\n[^\n]*\z//;
    1 while s/\n+\z// or s/\n#[^\n]*\z//;
    $_ .= $more;
  }
' release-notes.tmp
mkdir -p manifests/f/Freelensapp/Freelens/"${version}"

yq '
  .PackageVersion = "'"${version}"'" |
  .ReleaseDate = "'"${releaseDate}"'" |
  .AppsAndFeaturesEntries[0].DisplayName = "Freelens '"${version}"'" |
  (.Installers.[] | select(.Architecture == "x64").InstallerUrl) = "'"${installerX64Url}"'" |
  (.Installers.[] | select(.Architecture == "x64").InstallerSha256) = "'"${installerX64Sha256}"'" |
  (.Installers.[] | select(.Architecture == "arm64").InstallerUrl) = "'"${installerArm64Url}"'" |
  (.Installers.[] | select(.Architecture == "arm64").InstallerSha256) = "'"${installerArm64Sha256}"'"
' template/Freelensapp.Freelens.installer.yaml \
  >manifests/f/Freelensapp/Freelens/"${version}"/Freelensapp.Freelens.installer.yaml

yq '
  .PackageVersion = "'"${version}"'" |
  .ReleaseNotes = load_str("release-notes.tmp") |
  .ReleaseNotesUrl = "'"${releaseUrl}"'"
' template/Freelensapp.Freelens.locale.en-US.yaml \
  >manifests/f/Freelensapp/Freelens/"${version}"/Freelensapp.Freelens.locale.en-US.yaml

yq '
  .PackageVersion = "'"${version}"'"
' template/Freelensapp.Freelens.yaml \
  >manifests/f/Freelensapp/Freelens/"${version}"/Freelensapp.Freelens.yaml

yamlfmt -conf template/.yamlfmt.yaml manifests/f/Freelensapp/Freelens/"${version}"/*.yaml
