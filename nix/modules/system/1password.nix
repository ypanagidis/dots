{
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "yiannis" ];
  };

  # Let the desktop app unlock the extension in Helium. 1Password only trusts
  # a small built-in browser list on Linux, so custom browsers must be named
  # explicitly in this root-owned file.
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      helium
    '';
    mode = "0755";
  };
}
