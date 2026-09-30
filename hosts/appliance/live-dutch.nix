# Firefox in Dutch on the live USB (issue #180).
#
# DAWO-Core lists the Dutch language pack (`programs.firefox.languagePacks`),
# but nixpkgs installs it through the ExtensionSettings policy with an
# install_url on releases.mozilla.org: Firefox downloads it at start. On the
# live USB every boot has a fresh Firefox profile and Firefox starts at login,
# before the wifi is up, so the pack never arrived and Firefox (its menus and
# the Accept-Language it sends to Keycloak, Nextcloud, Element, Collabora)
# stayed English. Here the pack is part of the image (pinned by version and
# hash, installed from file://) and Dutch is the requested UI and content
# language.
#
# Experimental and unofficial. Not for production.
{ config, lib, pkgs, ... }:

let
  # Must match the Firefox in the image: a language pack only loads into the
  # exact version it was built for. The assertion below catches a Firefox bump.
  firefoxVersion = "153.0.3";
  langpackNl = pkgs.fetchurl {
    url = "https://releases.mozilla.org/pub/firefox/releases/${firefoxVersion}/linux-x86_64/xpi/nl.xpi";
    sha256 = "0rh0kw91bhb0815i30nsmv8wndnqw1x1lgjfafm7lb3drj3pmlip";
  };
in
{
  assertions = [{
    assertion = config.programs.firefox.package.version == firefoxVersion;
    message = "hosts/appliance/live-dutch.nix: Firefox is ${config.programs.firefox.package.version}, the pinned Dutch language pack is for ${firefoxVersion}; update firefoxVersion and the hash (#180).";
  }];

  programs.firefox.policies = {
    # Replaces upstream's download URL for this one pack (same extension id).
    ExtensionSettings."langpack-nl@firefox.mozilla.org" = lib.mkForce {
      installation_mode = "force_installed";
      install_url = "file://${langpackNl}";
    };
    RequestedLocales = [ "nl" ];
  };
  programs.firefox.preferences = {
    "intl.locale.requested" = "nl";
    "intl.accept_languages" = "nl-NL, nl, en-US, en";
  };
}
