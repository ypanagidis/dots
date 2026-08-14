{ ... }:
{

  programs.btop = {
    enable = true;
    themes = {
      catppuccin-latte = ./catppuccin_latte.theme;
      ayu-mirage = ./ayu-mirage.theme;
      cyberdream = ./cyberdream.theme;
    };

    settings = {
      color_theme = "cyberdream";
    };
  };
}
