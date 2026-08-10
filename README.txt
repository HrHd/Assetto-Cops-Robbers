============================================================
  Cops & Robbers v1.0
  By Jp
============================================================

A competitive cops vs robbers gamemode app for Assetto Corsa.
Requires Custom Shaders Patch (CSP) 0.1.79+.


FEATURES
--------

  Both Teams:
  - Tap any car or wall -> teleport to random spawn point
  - Toggleable collision triggers (walls, cars, or both)
  - Adjustable sensitivity, cooldown, detection range, min speed
  - Compact mode to hide non-essential UI
  - Score display with manual adjuster in Settings
  - Handshake status indicator in title bar

  Cop Mode:
  - Radar gun with signal strength (S1-S9), real-time speed/distance
  - Hold lock keybind (4s) to hard-lock a target in the beam
  - Target must stay in radar cone or lock cancels
  - 75m range, ~18 degree cone, ignores AI and 350+ km/h
  - Locked targets persist until manually cleared
  - Manual spawn selection (pick your PA before chasing)
  - Reset radar button to clear all tracking

  Robber Mode:
  - Radar detector with Ka-band frequency readout + signal bars
  - Sawtooth chirp with distance-based pitch/interval
  - Direction arrows (L/R/A/!) and threat coloring
  - Proximity-based lock detection (cop behind for 4s)
  - Chase system: lock -> chase (8s) -> search phase (60s)
  - Targeted alert when cop within 27m behind + speeding
  - Quick mute keybind for the chirp
  - Chase reset button to clear stuck state


INSTALLATION
------------

  Method 1: Drag-and-drop CopsAndRobbers_By_Jp.zip onto
            Content Manager (auto-installs).

  Method 2: Extract to your AC root folder:
            <assettocorsa>/apps/lua/cops_and_robbers/

  Enable the app in-game via the apps sidebar.


KEYBINDS (Settings -> Controls)
--------------------------------

  CopsAndRobbers/LockTarget   - Hold to lock nearest speeder (cop only)
  CopsAndRobbers/MuteChirp    - Toggle radar chirp on/off (robber only)

  Both keybinds are team-gated and can share the same physical key.


SPAWN POINTS
------------

  Online: Server TELEPORT_DESTINATIONS load automatically.
          (SRP, No Hesi 415/110 servers ship with these.)

  Offline: Create spawn configs at:
           apps/lua/cops_and_robbers/spawns/<track_id>.ini

  Format (see spawns/example_format.ini):
    [SPAWN_0]
    NAME = My Spot
    POS = 123.45, 0.50, 678.90
    HEADING = 180

  Cops can manually select a spawn in Settings -> Cop Spawn.


SETTINGS
--------

  General:
  - Enable/Disable
  - Wall collisions / Car collisions trigger
  - Sensitivity, detection range, min speed, cooldown

  Scores:
  - Manual +/- adjusters per team
  - Reset Scores button

  Robber Radar:
  - Beep audio on/off
  - Beep volume (0.1 - 2.0)
  - Chirp speed multiplier (0.3x - 3.0x)
  - Mute keybind

  Cop Radar:
  - Speed limit (30 - 300 km/h)
  - Lock target keybind

  Cop Spawn:
  - Random (default) or select from spawn list


SCORING
-------

  Scores are fully manual — use the +/- buttons in Settings
  to add or remove points. No automatic detection.


CREDITS
-------

  By Jp
  Built with CSP Lua SDK
  https://github.com/ac-custom-shaders-patch/acc-lua-sdk


CHANGELOG
---------

  v1.0 - Initial release
  - Cop radar gun with beam targeting + hard lock
  - Robber radar detector with Ka-band display + chirp
  - Chase system with lock/search phases
  - Server teleport integration (SRP/415/110)
  - Manual scoring with adjuster buttons
  - Compact mode, keybinds, spawn selector
