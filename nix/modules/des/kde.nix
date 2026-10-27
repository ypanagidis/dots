{ pkgs, lib, ... }:

let
  # Plasma occasionally forgets the panel hiding mode after sleep/resume. This
  # script is safe to run repeatedly: it only touches bottom panels and leaves
  # every other panel alone.
  enforceBottomPanelAutohide = pkgs.writeShellScript "kde-bottom-panel-autohide" ''
    set -euo pipefail

    plasma_script='for (const panel of panels()) { if (panel.location === "bottom" || panel.location === 4) { panel.hiding = "autohide"; } }'

    # Use busctl instead of qdbus so this does not depend on an extra Qt tools
    # binary being installed. If plasmashell is not ready yet, fail softly; the
    # timer below will retry shortly.
    ${pkgs.systemd}/bin/busctl --user --timeout=5 call \
      org.kde.plasmashell \
      /PlasmaShell \
      org.kde.PlasmaShell \
      evaluateScript \
      s "$plasma_script" >/dev/null 2>&1 || true
  '';

  # One-shot KWin script behind `kde-apps comms`: Slack, Telegram, Discord
  # top to bottom in equal thirds of HDMI-A-1 (the portrait screen niri uses
  # for comms), or side by side on the active screen if HDMI-A-1 is missing.
  # Only the apps that have a window take part.
  commsLayout = pkgs.writeText "kde-comms-layout.js" ''
    const order = ["slack", "org.telegram.desktop", "discord"];
    const output = workspace.screens.find((o) => o.name === "HDMI-A-1") || workspace.activeScreen;
    const area = workspace.clientArea(KWin.MaximizeArea, output, workspace.currentDesktop);
    const wins = order
      .map((id) => workspace.windowList().find((w) =>
        w.normalWindow && (w.resourceClass.toLowerCase() === id || w.desktopFileName === id)))
      .filter((w) => w);
    const vertical = area.height >= area.width;
    const span = vertical ? area.height : area.width;
    wins.forEach((w, i) => {
      const from = Math.round((i * span) / wins.length);
      const to = Math.round(((i + 1) * span) / wins.length);
      w.minimized = false;
      w.fullScreen = false;
      w.setMaximize(false, false);
      w.frameGeometry = vertical
        ? { x: area.x, y: area.y + from, width: area.width, height: to - from }
        : { x: area.x + from, y: area.y, width: to - from, height: area.height };
    });
    // Raise all three, ending on Slack.
    wins.slice().reverse().forEach((w) => { workspace.activeWindow = w; });
  '';

  # Hyper-key helpers for apps that aren't taskbar pins (Plasma only has
  # shortcuts for the first 10 pins).
  #   kde-apps focus <window-class> <desktop-id>
  #     Focus the app's window, or launch it from its desktop entry if it has
  #     none (also reopens apps hiding in the tray). Pressing again while it's
  #     focused cycles through its windows.
  #   kde-apps comms
  #     Open whichever of Slack/Telegram/Discord has no window, then tile all
  #     three with commsLayout. Window classes double as desktop ids here.
  # Wispr Flow's status pill is an always-on-top, transparent 512x614 X11
  # window at the bottom middle of a screen. Electron's setIgnoreMouseEvents
  # never reaches X11 here, so the whole box keeps an input region and eats
  # clicks meant for whatever is underneath (Spotify's player controls on
  # DP-2). This watches for the pill being mapped and empties its input
  # region; the pill still shows and works from the hotkey, it just can't be
  # clicked or dragged.
  wisprPillClickThrough =
    pkgs.writers.writePython3Bin "wispr-pill-click-through"
      { libraries = [ pkgs.python3Packages.xlib ]; }
      ''
        import select

        from Xlib import X, Xatom, display
        from Xlib.ext import shape

        # Created as "Flow Status Indicator"; the page retitles it "Status".
        TITLES = {"Status", "Flow Status Indicator"}

        d = display.Display()
        d.set_error_handler(lambda *_: None)  # windows can vanish mid-check
        root = d.screen().root
        net_wm_name = d.intern_atom("_NET_WM_NAME")
        pills = {}


        def consider(w):
            # The pill often maps before its title is set, so also watch the
            # title of every window that might still turn into it.
            try:
                w.change_attributes(event_mask=X.PropertyChangeMask)
                cls = w.get_wm_class()
                title = w.get_full_text_property(net_wm_name) or w.get_wm_name()
            except Exception:
                return
            if cls and cls[0] == "wispr-flow" and title in TITLES:
                pills[w.id] = w


        def clear_pills():
            # Wispr resets the input region without a ShapeNotify, so this
            # runs on every event and on a short timer.
            for wid, w in list(pills.items()):
                try:
                    if w.shape_get_rectangles(shape.SK.Input).rectangles:
                        w.shape_rectangles(
                            shape.SO.Set, shape.SK.Input, X.Unsorted, 0, 0, []
                        )
                except Exception:
                    del pills[wid]  # destroyed
            d.flush()


        root.change_attributes(event_mask=X.SubstructureNotifyMask)
        for w in root.query_tree().children:
            consider(w)
        while True:
            clear_pills()
            if not d.pending_events():
                select.select([d], [], [], 0.5)
            while d.pending_events():
                event = d.next_event()
                if event.type == X.MapNotify:
                    consider(event.window)
                elif event.type == X.PropertyNotify and event.atom in (
                    net_wm_name,
                    Xatom.WM_NAME,
                ):
                    consider(event.window)
      '';

  kdeApps = pkgs.writeShellApplication {
    name = "kde-apps";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.kdotool
      pkgs.kdePackages.kde-cli-tools
      pkgs.systemd
    ];
    text = ''
      # Window ids whose class is exactly $1 (kdotool takes a regex).
      windows() { kdotool search --class "^''${1//./\\.}$" 2>/dev/null || true; }

      launch() { kstart --application "$1" >/dev/null 2>&1; }

      focus() {
        local class="$1" desktop="$2" ids active next
        ids="$(windows "$class")"
        if [ -z "$ids" ]; then
          launch "$desktop"
          return
        fi
        active="$(kdotool getactivewindow 2>/dev/null || true)"
        # The window after the active one, wrapping; the first if none is active.
        next="$(printf '%s\n' "$ids" | awk -v a="$active" '
          NR == 1 { first = $0 }
          hit { print; found = 1; exit }
          $0 == a { hit = 1 }
          END { if (!found) print first }
        ')"
        kdotool windowactivate "$next"
      }

      comms() {
        local apps=(slack org.telegram.desktop discord) launched=() app
        for app in "''${apps[@]}"; do
          if [ -z "$(windows "$app")" ]; then
            launch "$app" || continue
            launched+=("$app")
          fi
        done
        if [ "''${#launched[@]}" -gt 0 ]; then
          # Wait up to 20s for the new windows, then give Electron a moment to
          # settle its own initial size before we override it.
          for _ in $(seq 100); do
            missing=0
            for app in "''${launched[@]}"; do
              [ -n "$(windows "$app")" ] || missing=1
            done
            [ "$missing" -eq 0 ] && break
            sleep 0.2
          done
          sleep 1
        fi

        local name=kde-apps-comms id
        busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting \
          unloadScript s "$name" >/dev/null 2>&1 || true
        id="$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting \
          loadScript ss ${commsLayout} "$name" | awk '{print $2}')"
        busctl --user call org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script run >/dev/null
        busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting \
          unloadScript s "$name" >/dev/null
      }

      case "''${1:-}" in
        focus) focus "$2" "$3" ;;
        comms) comms ;;
        *)
          echo "usage: kde-apps focus <window-class> <desktop-id> | kde-apps comms" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  programs.plasma = {
    enable = true;
    overrideConfig = true;
    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";
      colorScheme = "BreezeDark";
      theme = "breeze-dark";
    };
    # Never suspend on idle; the screens still dim and turn off. The display
    # timers match Plasma's defaults, pinned so an upstream change can't move
    # them.
    powerdevil.AC = {
      autoSuspend.action = "nothing";
      powerButtonAction = "showLogoutScreen";
      dimDisplay.idleTimeout = 300;
      turnOffDisplay = {
        idleTimeout = 600;
        idleTimeoutWhenLocked = 60;
      };
    };
    startup.desktopScript.bottom-panel-autohide = {
      runAlways = true;
      priority = 4;
      text = ''
        // Initial login-time enforcement. A user timer below keeps this sticky
        // after sleep/resume because Plasma sometimes resets panel hiding.
        for (const panel of panels()) {
          if (panel.location === "bottom" || panel.location === 4) {
            panel.hiding = "autohide";
          }
        }
      '';
    };
    shortcuts = {
      "KDE Keyboard Layout Switcher"."Switch to Last-Used Keyboard Layout" = "Meta+Alt+L";
      "KDE Keyboard Layout Switcher"."Switch to Next Keyboard Layout" = "Meta+Alt+K";
      kaccess."Toggle Screen Reader On and Off" = "Meta+Alt+S";
      kmix.decrease_microphone_volume = "Microphone Volume Down";
      kmix.decrease_volume = "Volume Down";
      kmix.decrease_volume_small = "Shift+Volume Down";
      kmix.increase_microphone_volume = "Microphone Volume Up";
      kmix.increase_volume = "Volume Up";
      kmix.increase_volume_small = "Shift+Volume Up";
      kmix.mic_mute = [
        "Microphone Mute"
        "Meta+Volume Mute"
      ];
      kmix.mute = "Volume Mute";
      ksmserver."Lock Session" = [
        "Meta+L"
        "Screensaver"
      ];
      ksmserver."Log Out" = "Ctrl+Alt+Del";
      kwin."Activate Window Demanding Attention" = "Meta+Ctrl+A";
      kwin."Edit Tiles" = "Meta+T";
      kwin.Expose = "Ctrl+F9";
      kwin.ExposeAll = [
        "Ctrl+F10"
        "Launch (C)"
      ];
      kwin.ExposeClass = "Ctrl+F7";
      kwin."Grid View" = [ ];
      kwin."Kill Window" = "Meta+Ctrl+Esc";
      kwin.MoveMouseToCenter = "Meta+F6";
      kwin.MoveMouseToFocus = "Meta+F5";
      kwin.Overview = "Meta+W";
      kwin."Show Desktop" = "Meta+D";
      kwin."Switch One Desktop Down" = "Meta+Ctrl+Down";
      kwin."Switch One Desktop Up" = "Meta+Ctrl+Up";
      kwin."Switch One Desktop to the Left" = "Meta+Ctrl+Left";
      kwin."Switch One Desktop to the Right" = "Meta+Ctrl+Right";
      kwin."Switch Window Down" = "Meta+Alt+Down";
      kwin."Switch Window Left" = "Meta+Alt+Left";
      kwin."Switch Window Right" = "Meta+Alt+Right";
      kwin."Switch Window Up" = "Meta+Alt+Up";
      kwin."Switch to Desktop 1" = "Ctrl+F1";
      kwin."Switch to Desktop 2" = "Ctrl+F2";
      kwin."Switch to Desktop 3" = "Ctrl+F3";
      kwin."Switch to Desktop 4" = "Ctrl+F4";
      kwin."Walk Through Windows" = [
        "Meta+Tab"
        "Alt+Tab"
      ];
      kwin."Walk Through Windows (Reverse)" = [
        "Meta+Shift+Tab"
        "Alt+Shift+Tab"
      ];
      kwin."Walk Through Windows of Current Application" = [
        "Meta+`"
        "Alt+`"
      ];
      kwin."Walk Through Windows of Current Application (Reverse)" = [
        "Meta+~"
        "Alt+~"
      ];
      kwin."Window Close" = "Alt+F4";
      kwin."Window Maximize" = [
        "Meta+PgUp"
        "Ctrl+Shift+M"
      ];
      kwin."Window Minimize" = "Meta+PgDown";
      kwin."Window One Desktop Down" = "Meta+Ctrl+Shift+Down";
      kwin."Window One Desktop Up" = "Meta+Ctrl+Shift+Up";
      kwin."Window One Desktop to the Left" = "Meta+Ctrl+Shift+Left";
      kwin."Window One Desktop to the Right" = "Meta+Ctrl+Shift+Right";
      kwin."Window One Screen Down" = "Meta+Shift+J";
      kwin."Window One Screen Up" = "Meta+Shift+K";
      kwin."Window One Screen to the Left" = "Meta+Shift+H";
      kwin."Window One Screen to the Right" = "Meta+Shift+L";
      kwin."Window Operations Menu" = "Alt+F3";
      kwin."Window Quick Tile Bottom" = [
        "Meta+Down"
        "Ctrl+Shift+J"
      ];
      kwin."Window Quick Tile Left" = [
        "Meta+Left"
        "Ctrl+Shift+H"
      ];
      kwin."Window Quick Tile Right" = [
        "Meta+Right"
        "Ctrl+Shift+L"
      ];
      kwin."Window Quick Tile Top" = [
        "Ctrl+Shift+K"
        "Meta+Up"
      ];
      kwin."Window to Next Screen" = "Meta+Shift+Right";
      kwin."Window to Previous Screen" = "Meta+Shift+Left";
      kwin.disableInputCapture = "Meta+Shift+Esc";
      kwin.view_actual_size = "Meta+0";
      kwin.view_zoom_in = [
        "Meta++"
        "Meta+="
      ];
      kwin.view_zoom_out = "Meta+-";
      mediacontrol.nextmedia = "Media Next";
      mediacontrol.pausemedia = "Media Pause";
      mediacontrol.playpausemedia = "Media Play";
      mediacontrol.previousmedia = "Media Previous";
      mediacontrol.stopmedia = "Media Stop";
      org_kde_powerdevil."Decrease Keyboard Brightness" = "Keyboard Brightness Down";
      org_kde_powerdevil."Decrease Screen Brightness" = "Monitor Brightness Down";
      org_kde_powerdevil."Decrease Screen Brightness Small" = "Shift+Monitor Brightness Down";
      org_kde_powerdevil.Hibernate = "Hibernate";
      org_kde_powerdevil."Increase Keyboard Brightness" = "Keyboard Brightness Up";
      org_kde_powerdevil."Increase Screen Brightness" = "Monitor Brightness Up";
      org_kde_powerdevil."Increase Screen Brightness Small" = "Shift+Monitor Brightness Up";
      org_kde_powerdevil.PowerDown = "Power Down";
      org_kde_powerdevil.PowerOff = "Power Off";
      org_kde_powerdevil.Sleep = "Sleep";
      org_kde_powerdevil."Toggle Keyboard Backlight" = "Keyboard Light On/Off";
      org_kde_powerdevil.powerProfile = [
        "Battery"
        "Meta+B"
      ];
      plasmashell."activate application launcher" = [
        "Alt+F1"
        "Alt+Space"
      ];
      # Hyper+<letter> focuses the pinned app, or launches it if it isn't
      # running: A = browser, C = ghostty, D = discord, and so on.
      plasmashell."activate task manager entry 1" = [
        "Meta+1"
        "Meta+Ctrl+Alt+Shift+A"
      ];
      plasmashell."activate task manager entry 2" = [
        "Meta+2"
        "Meta+Ctrl+Alt+Shift+C"
      ];
      plasmashell."activate task manager entry 3" = [
        "Meta+3"
        "Meta+Ctrl+Alt+Shift+D"
      ];
      plasmashell."activate task manager entry 4" = [
        "Meta+4"
        "Meta+Ctrl+Alt+Shift+T"
      ];
      plasmashell."activate task manager entry 5" = [
        "Meta+5"
        "Meta+Ctrl+Alt+Shift+O"
      ];
      plasmashell."activate task manager entry 6" = [
        "Meta+6"
        "Meta+Ctrl+Alt+Shift+P"
      ];
      plasmashell."activate task manager entry 7" = [
        "Meta+Ctrl+Alt+Shift+M"
        "Meta+7"
      ];
      plasmashell."activate task manager entry 8" = [
        "Meta+Ctrl+Alt+Shift+R"
        "Meta+Ctrl+Alt+Shift+G"
        "Meta+8"
      ];
      plasmashell."activate task manager entry 9" = "Meta+9";
      plasmashell.clipboard_action = "Meta+Ctrl+X";
      plasmashell.cycle-panels = "Meta+Alt+P";
      plasmashell."manage activities" = "Meta+Q";
      plasmashell."next activity" = "Meta+A";
      plasmashell."previous activity" = "Meta+Shift+A";
      plasmashell."show dashboard" = "Ctrl+F12";
      plasmashell.show-on-mouse-pos = "Meta+V";
      "services/org.kde.spectacle.desktop"._launch = [
        "Print"
        "Ctrl+#"
      ];
    };
    # Meta+Shift+S: draw a region, image lands on the clipboard, no window —
    # same flow as the old grim/slurp binding on niri. (-r region, -b no GUI,
    # -c clipboard)
    hotkeys.commands.spectacle-region-clipboard = {
      name = "Region screenshot to clipboard";
      key = "Meta+Shift+S";
      command = "spectacle -r -b -c";
    };
    hotkeys.commands.focus-t3-code = {
      name = "Focus or launch T3 Code";
      key = "Meta+Ctrl+Alt+Shift+F";
      command = "${kdeApps}/bin/kde-apps focus com.t3tools.T3Code t3-code";
    };
    hotkeys.commands.focus-slack = {
      name = "Focus or launch Slack";
      key = "Meta+Ctrl+Alt+Shift+S";
      command = "${kdeApps}/bin/kde-apps focus slack slack";
    };
    # Hyper+V, same as niri-ctx comms.
    hotkeys.commands.comms-layout = {
      name = "Open and tile Slack, Telegram, Discord";
      key = "Meta+Ctrl+Alt+Shift+V";
      command = "${kdeApps}/bin/kde-apps comms";
    };
    window-rules = [
      {
        description = "OpenCode Desktop without titlebar";
        match = {
          window-class = {
            value = "electron";
            type = "exact";
            match-whole = false;
          };
          title = {
            value = "OpenCode";
            type = "exact";
          };
        };
        apply.noborder = {
          value = true;
          apply = "force";
        };
      }
    ];
    configFile = {
      baloofilerc.General.dbVersion = 2;
      baloofilerc.General."exclude filters" =
        "*~,*.part,*.o,*.la,*.lo,*.loT,*.moc,moc_*.cpp,qrc_*.cpp,ui_*.h,cmake_install.cmake,CMakeCache.txt,CTestTestfile.cmake,libtool,config.status,confdefs.h,autom4te,conftest,confstat,Makefile.am,*.gcode,.ninja_deps,.ninja_log,build.ninja,*.csproj,*.m4,*.rej,*.gmo,*.pc,*.omf,*.aux,*.tmp,*.po,*.vm*,*.nvram,*.rcore,*.swp,*.swap,lzo,litmain.sh,*.orig,.histfile.*,.xsession-errors*,*.map,*.so,*.a,*.db,*.qrc,*.ini,*.init,*.img,*.vdi,*.vbox*,vbox.log,*.qcow2,*.vmdk,*.vhd,*.vhdx,*.sql,*.sql.gz,*.ytdl,*.tfstate*,*.class,*.pyc,*.pyo,*.elc,*.qmlc,*.jsc,*.fastq,*.fq,*.gb,*.fasta,*.fna,*.gbff,*.faa,po,CVS,.svn,.git,_darcs,.bzr,.hg,CMakeFiles,CMakeTmp,CMakeTmpQmake,.moc,.obj,.pch,.uic,.npm,.yarn,.yarn-cache,__pycache__,node_modules,node_packages,nbproject,.terraform,.venv,venv,core-dumps,lost+found";
      baloofilerc.General."exclude filters version" = 9;
      dolphinrc.General.ViewPropsTimestamp = "2025,12,25,3,11,27.774";
      dolphinrc."KFileDialog Settings"."Places Icons Auto-resize" = false;
      dolphinrc."KFileDialog Settings"."Places Icons Static Size" = 22;
      kactivitymanagerdrc.activities."88c96075-3fd2-47a6-90e6-70f9b4556a51" = "Default";
      kactivitymanagerdrc.main.currentActivity = "88c96075-3fd2-47a6-90e6-70f9b4556a51";
      katerc.General."Days Meta Infos" = 30;
      katerc.General."Save Meta Infos" = true;
      katerc.General."Show Full Path in Title" = false;
      katerc.General."Show Menu Bar" = true;
      katerc.General."Show Status Bar" = true;
      katerc.General."Show Tab Bar" = true;
      katerc.General."Show Url Nav Bar" = true;
      katerc.filetree.editShade = "30,78,103";
      katerc.filetree.listMode = false;
      katerc.filetree.middleClickToClose = false;
      katerc.filetree.shadingEnabled = true;
      katerc.filetree.showCloseButton = false;
      katerc.filetree.showFullPathOnRoots = false;
      katerc.filetree.showToolbar = true;
      katerc.filetree.sortRole = 0;
      katerc.filetree.viewShade = "77,46,91";
      katerc.lspclient.AllowedServerCommandLines = "";
      katerc.lspclient.AutoHover = true;
      katerc.lspclient.AutoImport = true;
      katerc.lspclient.BlockedServerCommandLines = "/run/current-system/sw/bin/nil";
      katerc.lspclient.CompletionDocumentation = true;
      katerc.lspclient.CompletionParens = true;
      katerc.lspclient.Diagnostics = true;
      katerc.lspclient.FormatOnSave = false;
      katerc.lspclient.HighlightGoto = true;
      katerc.lspclient.HighlightSymbol = true;
      katerc.lspclient.IncrementalSync = false;
      katerc.lspclient.InlayHints = false;
      katerc.lspclient.Messages = true;
      katerc.lspclient.ReferencesDeclaration = true;
      katerc.lspclient.SemanticHighlighting = true;
      katerc.lspclient.ServerConfiguration = "";
      katerc.lspclient.ShowCompletions = true;
      katerc.lspclient.SignatureHelp = true;
      katerc.lspclient.SymbolDetails = false;
      katerc.lspclient.SymbolExpand = true;
      katerc.lspclient.SymbolSort = false;
      katerc.lspclient.SymbolTree = true;
      katerc.lspclient.TypeFormatting = false;
      kcminputrc.Keyboard.RepeatDelay = 200;
      kcminputrc.Keyboard.RepeatRate = 50;
      # Applies to every pointer device (KWin's [Libinput][Defaults][Pointer]
      # fallback) — no more per-mouse vendor/product entries.
      kcminputrc."Libinput/Defaults/Pointer".NaturalScroll = true;
      kded5rc.Module-browserintegrationreminder.autoload = false;
      kded5rc.Module-device_automounter.autoload = false;
      kdeglobals.General.TerminalApplication = "${pkgs.ghostty}/bin/ghostty --gtk-single-instance=true";
      kdeglobals.General.TerminalService = "com.mitchellh.ghostty.desktop";
      kdeglobals."KFileDialog Settings"."Allow Expansion" = false;
      kdeglobals."KFileDialog Settings"."Automatically select filename extension" = true;
      kdeglobals."KFileDialog Settings"."Breadcrumb Navigation" = false;
      kdeglobals."KFileDialog Settings"."Decoration position" = 2;
      kdeglobals."KFileDialog Settings"."Show Full Path" = false;
      kdeglobals."KFileDialog Settings"."Show Inline Previews" = true;
      kdeglobals."KFileDialog Settings"."Show Preview" = false;
      kdeglobals."KFileDialog Settings"."Show Speedbar" = true;
      kdeglobals."KFileDialog Settings"."Show hidden files" = false;
      kdeglobals."KFileDialog Settings"."Sort by" = "Date";
      kdeglobals."KFileDialog Settings"."Sort directories first" = true;
      kdeglobals."KFileDialog Settings"."Sort hidden files last" = true;
      kdeglobals."KFileDialog Settings"."Sort reversed" = false;
      kdeglobals."KFileDialog Settings"."Speedbar Width" = 140;
      kdeglobals."KFileDialog Settings"."View Style" = "DetailTree";
      kdeglobals.KScreen.ScreenScaleFactors = "DP-1=1;DP-2=1;";
      kdeglobals.WM.activeBackground = "39,44,49";
      kdeglobals.WM.activeBlend = "252,252,252";
      kdeglobals.WM.activeForeground = "252,252,252";
      kdeglobals.WM.inactiveBackground = "32,36,40";
      kdeglobals.WM.inactiveBlend = "161,169,177";
      kdeglobals.WM.inactiveForeground = "161,169,177";
      kscreenlockerrc.Daemon.Timeout = 30;
      # Start a clean KDE session instead of restoring whatever was open at the
      # last logout. This prevents Remmina (and other old session windows) from
      # popping back up on login.
      ksmserverrc.General.loginMode = "emptySession";
      ksmserverrc.General.excludeApps = "remmina";
      kwalletrc.Wallet."Close When Idle" = false;
      kwalletrc.Wallet."Close on Screensaver" = false;
      kwalletrc.Wallet."Default Wallet" = "kdewallet";
      kwalletrc.Wallet.Enabled = true;
      kwalletrc.Wallet."First Use" = false;
      kwalletrc.Wallet."Idle Timeout" = 10;
      kwalletrc.Wallet."Launch Manager" = true;
      kwalletrc.Wallet."Leave Manager Open" = true;
      kwalletrc.Wallet."Leave Open" = false;
      kwalletrc.Wallet."Prompt on Open" = false;
      kwalletrc.Wallet."Use One Wallet" = true;
      kwalletrc."org.freedesktop.secrets".apiEnabled = true;
      kwinrc.Desktops.Id_1 = "6c7ed35d-a893-4861-a4d8-e10caa85be7d";
      kwinrc.Desktops.Number = 1;
      kwinrc.Desktops.Rows = 1;
      # New windows open on the screen the mouse is on — niri's mouse-driven
      # output model, instead of "primary display" or last-focused guessing.
      kwinrc.Windows.ActiveMouseScreen = true;
      kwinrc.Tiling."[Tiling][6c7ed35d-a893-4861-a4d8-e10caa85be7d][]" = "";
      kwinrc.Tiling.padding = 4;
      kwinrc.Tiling.tiles = "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/6c7ed35d-a893-4861-a4d8-e10caa85be7d/319fcac6-45a3-4c13-8739-30df2f495ab9".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/6c7ed35d-a893-4861-a4d8-e10caa85be7d/63fc4d86-1d2e-467b-b165-60eb2c15b9a2".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/6c7ed35d-a893-4861-a4d8-e10caa85be7d/82bf5249-2a13-40bb-94bd-3665a69062a8".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/6c7ed35d-a893-4861-a4d8-e10caa85be7d/d0070d28-5836-45bb-ad10-5b7a8a8139a3".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc."Tiling/6c7ed35d-a893-4861-a4d8-e10caa85be7d/db303164-d914-4053-b18a-b8672a2323e9".tiles =
        "{\"layoutDirection\":\"horizontal\",\"tiles\":[{\"width\":0.25},{\"width\":0.5},{\"width\":0.25}]}";
      kwinrc.Xwayland.Scale = 2;
      plasma-localerc.Formats.LANG = "en_US.UTF-8";
      plasmanotifyrc."Applications/chromium-browser".Seen = true;
      plasmanotifyrc."Applications/com.mitchellh.ghostty".Seen = true;
      plasmanotifyrc."Applications/discord".Seen = true;
      plasmanotifyrc."Applications/google-chrome".Seen = true;
      plasmanotifyrc."Applications/helium".Seen = true;
      plasmarc.Wallpapers.usersWallpapers = "";
      # NOTE: applet IDs are machine-specific — 4/7 is the icontasks applet on
      # this install (was 3/30 on the old machine). If the panel is ever
      # recreated, re-check with: grep -B20 icontasks plasma-org...appletsrc
      "plasma-org.kde.plasma.desktop-appletsrc"."Containments/4/Applets/7/Configuration/General".launchers =
        {
          value = "applications:helium.desktop,applications:com.mitchellh.ghostty.desktop,applications:discord.desktop,applications:spotify.desktop,applications:obsidian.desktop,applications:datagrip.desktop,applications:bruno.desktop,applications:systemsettings.desktop,preferred://filemanager,applications:t3-code.desktop";
          escapeValue = false;
        };
      # T3 Code writes its own hidden com.t3tools.T3Code.desktop, which would
      # win the app-id match and leave the window ungrouped from the pin above.
      # Map the app id to ours.
      taskmanagerrulesrc.Mapping."com.t3tools.T3Code" = "t3-code";
      # Capture the region on mouse release — no separate Accept click.
      spectaclerc.General.useReleaseToCapture = true;
      # Klipper drops image clipboard entries by default; without this the
      # screenshot vanishes from the clipboard the moment spectacle -b exits.
      klipperrc.General.IgnoreImages = false;
      spectaclerc.Annotations.annotationToolType = 9;
      spectaclerc.Annotations.highlighterStrokeWidth = 27;
      spectaclerc.ImageSave.lastImageSaveLocation = "file:///home/yiannis/Pictures/Screenshots/Screenshot_20260129_020102.png";
      spectaclerc.ImageSave.translatedScreenshotsFolder = "Screenshots";
      spectaclerc.VideoSave.translatedScreencastsFolder = "Screencasts";
    };
    dataFile = {
      "kate/anonymous.katesession"."Document 0".URL = "file:///home/yiannis/.config/ghostty/config";
      "kate/anonymous.katesession"."Kate Plugins".bookmarksplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".cmaketoolsplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".compilerexplorer = false;
      "kate/anonymous.katesession"."Kate Plugins".eslintplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".externaltoolsplugin = true;
      "kate/anonymous.katesession"."Kate Plugins".formatplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katebacktracebrowserplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katebuildplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katecloseexceptplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katecolorpickerplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katectagsplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katefilebrowserplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katefiletreeplugin = true;
      "kate/anonymous.katesession"."Kate Plugins".kategdbplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".kategitblameplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katekonsoleplugin = true;
      "kate/anonymous.katesession"."Kate Plugins".kateprojectplugin = true;
      "kate/anonymous.katesession"."Kate Plugins".katereplicodeplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katesearchplugin = true;
      "kate/anonymous.katesession"."Kate Plugins".katesnippetsplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katesqlplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katesymbolviewerplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katexmlcheckplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".katexmltoolsplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".keyboardmacrosplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".ktexteditorpreviewplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".latexcompletionplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".lspclientplugin = true;
      "kate/anonymous.katesession"."Kate Plugins".openlinkplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".rainbowparens = false;
      "kate/anonymous.katesession"."Kate Plugins".rbqlplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".tabswitcherplugin = true;
      "kate/anonymous.katesession"."Kate Plugins".templateplugin = false;
      "kate/anonymous.katesession"."Kate Plugins".textfilterplugin = true;
      "kate/anonymous.katesession".MainWindow0."Active ViewSpace" = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-H-Splitter = "0,2515,0";
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-0-Bar-0-TvList =
        "kate_private_plugin_katefiletreeplugin,kateproject,kateprojectgit,lspclient_symbol_outline";
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-0-LastSize = 200;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-0-SectSizes = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-0-Splitter = 1303;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-1-Bar-0-TvList = "";
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-1-LastSize = 200;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-1-SectSizes = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-1-Splitter = 1303;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-2-Bar-0-TvList = "";
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-2-LastSize = 200;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-2-SectSizes = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-2-Splitter = 2515;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-3-Bar-0-TvList =
        "output,diagnostics,kate_plugin_katesearch,kateprojectinfo,kate_private_plugin_katekonsoleplugin";
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-3-LastSize = 200;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-3-SectSizes = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-3-Splitter = 2268;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-Style = 2;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-Sidebar-Visible = true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-diagnostics-Position = 3;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-diagnostics-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-diagnostics-Visible = false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_plugin_katesearch-Position = 3;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_plugin_katesearch-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_plugin_katesearch-Visible = false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Position =
        0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_private_plugin_katefiletreeplugin-Visible =
        false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Position =
        3;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kate_private_plugin_katekonsoleplugin-Visible =
        false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateproject-Position = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateproject-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateproject-Visible = false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateprojectgit-Position = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateprojectgit-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateprojectgit-Visible = false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateprojectinfo-Position = 3;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateprojectinfo-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-kateprojectinfo-Visible = false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-lspclient_symbol_outline-Position = 0;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-lspclient_symbol_outline-Show-Button-In-Sidebar =
        true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-lspclient_symbol_outline-Visible = false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-output-Position = 3;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-output-Show-Button-In-Sidebar = true;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-ToolView-output-Visible = false;
      "kate/anonymous.katesession".MainWindow0.Kate-MDI-V-Splitter = "0,1303,0";
      "kate/anonymous.katesession"."MainWindow0 Settings".WindowState = 10;
      "kate/anonymous.katesession"."MainWindow0-Splitter 0".Children = "MainWindow0-ViewSpace 0";
      "kate/anonymous.katesession"."MainWindow0-Splitter 0".Orientation = 1;
      "kate/anonymous.katesession"."MainWindow0-Splitter 0".Sizes = 2515;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."Active View" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0".Count = 1;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0".Documents = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0"."View 0" = 0;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0 0".CursorColumn = 2;
      "kate/anonymous.katesession"."MainWindow0-ViewSpace 0 0".CursorLine = 0;
      "kate/anonymous.katesession"."Open Documents".Count = 1;
      "kate/anonymous.katesession"."Open MainWindows".Count = 1;
      "kate/anonymous.katesession"."Plugin:kateprojectplugin:".projects = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".BinaryFiles = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".CurrentExcludeFilter = "-1";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".CurrentFilter = "-1";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".ExcludeFilters = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".ExpandSearchResults = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".Filters = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".FollowSymLink = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".HiddenFiles = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".MatchCase = false;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".Place = 1;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".Recursive = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".Replaces = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".Search = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SearchAsYouTypeAllProjects =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SearchAsYouTypeCurrentFile =
        true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SearchAsYouTypeFolder = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SearchAsYouTypeOpenFiles = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SearchAsYouTypeProject = true;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SearchDiskFiles = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SearchDiskFiless = "";
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".SizeLimit = 128;
      "kate/anonymous.katesession"."Plugin:katesearchplugin:MainWindow:0".UseRegExp = false;
    };
  };

  systemd.user.services.kde-bottom-panel-autohide = {
    Unit = {
      Description = "Force KDE bottom panel autohide";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = enforceBottomPanelAutohide;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.timers.kde-bottom-panel-autohide = {
    Unit.Description = "Periodically reapply KDE bottom panel autohide";

    Timer = {
      # Run shortly after login, then keep correcting Plasma if sleep/resume or
      # a shell restart flips the panel back to always-visible.
      OnBootSec = "30s";
      OnUnitActiveSec = "2min";
      Unit = "kde-bottom-panel-autohide.service";
    };

    Install.WantedBy = [ "timers.target" ];
  };

  # Wispr Flow's own "open at login" is a no-op on Linux (Electron only
  # implements it on macOS/Windows), so start it with Plasma. Same flags as
  # its desktop entry: the X11 backend is what its hotkey capture needs.
  xdg.configFile."autostart/wispr-flow.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Wispr Flow
    Exec=${pkgs.wispr-flow}/bin/wispr-flow --ozone-platform=x11
    OnlyShowIn=KDE;
  '';
  xdg.configFile."autostart/wispr-pill-click-through.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Wispr Flow pill click-through
    Exec=${lib.getExe wisprPillClickThrough}
    OnlyShowIn=KDE;
    NoDisplay=true
  '';
}
