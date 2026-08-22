============================================================
  Cops & Robbers v1.0
  By Jp
============================================================

A competitive cops vs robbers gamemode app for Assetto Corsa.
Requires Custom Shaders Patch (CSP) 0.1.79+.


FEATURES
--------

  Both Teams:
  - Tap any car or wall -> teleport to pits / random spawn
  - Toggleable collision triggers (walls, cars, or both)
  - Adjustable sensitivity, cooldown, detection range, min speed
  - Compact mode to hide non-essential UI
  - Manual score adjuster in Settings
  - App ONLY runs when the main or mini radar window is open
  - Handshake status indicator in title bar

  Cop Mode:
  - Radar gun with signal strength (S1-S9), real-time speed/distance
  - Hold LockTarget keybind (4s) to hard-lock a target in the beam
  - Target must stay in the radar cone or lock cancels
  - Adjustable range (25-200m, default 75m), narrow ~18 degree cone
  - Ignores AI and cars above 350 km/h
  - Locked targets persist until manually cleared
  - Manual spawn selection (pick your PA before chasing)
  - Ticket Panel: 10 infractions, random fines, copy to clipboard
  - Refresh radar keybind to reset all tracking

  Robber Mode:
  - Radar detector with Ka-band readout + signal bars
  - Real radar audio: Ka voice alert once + chirps, Laser alert when targeted
  - 3 presets: Poor (750m), Decent (1000m), Good (1500m)
  - Proximity chase system: lock (4s) -> chase (adjustable, default 30s) -> search (60s)
  - ESCAPED! + Searching displays after losing the cop
  - Targeted alert when cop close behind + speeding
  - Quick mute keybind for the audio
  - Penalty Panel: timed infractions, speed limit + 5 enforcement
  - 10s over-limit warning before teleport to pits


INSTALLATION
------------

  Method 1: Drag-and-drop CopsAndRobbers_By_Jp.zip onto
            Content Manager (auto-installs).

  Method 2: Extract to your AC root folder:
            <assettocorsa>/apps/lua/cops_and_robbers/

  Enable the app in-game via the apps sidebar.


KEYBINDS (Settings -> Controls)
--------------------------------

  CopsAndRobbers/LockTarget    - Hold to lock nearest speeder (cop only)
  CopsAndRobbers/MuteChirp     - Toggle radar audio on/off (robber only)
  CopsAndRobbers/RefreshRadar  - Reset all radar state (both teams)

  Bind joystick/wheel buttons in AC Settings -> Controls ->
  scroll to the CopsAndRobbers section at the bottom.

  All keybinds are team-gated and can share the same physical key.


WINDOWS
-------

  Cops & Robbers  - Main window (radar, scores, status)
  Radar Mini      - Minimal popout radar window
  Ticket Panel    - Cop: issue tickets (copies to clipboard)
  Penalty Panel   - Robber: accept timed penalties

  The app only functions while the main or mini radar window is open.


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
  - Chirp speed multiplier (0.1x - 3.0x)
  - Chirp tone/pitch (0.3x - 3.0x)
  - Chase start time (10-120s, default 30s)
  - Radar presets: Poor / Decent / Good
  - Mute keybind

  Cop Radar:
  - Speed limit (30-300 km/h, default 160)
  - Radar range (25-200m, default 75m)
  - Lock target keybind
  - Refresh radar keybind

  Spawn:
  - Robber: Pits Only (default ON)
  - Cop: Random or manual spawn selection


SCORING
-------

  Scores are fully manual - use the +/- buttons in Settings
  to add or remove points. No automatic detection.


TICKETS & PENALTIES
-------------------

  Cop: Open Ticket Panel with a target locked, click an infraction.
       Ticket copies to clipboard, paste into chat.

  Robber: Open Penalty Panel and select the received infraction.
          Stay under speed limit + 5 km/h for the full duration.
          Exceeding for 10s -> teleported to pits.


CREDITS
-------

  By Jp
  Built with CSP Lua SDK
  https://github.com/ac-custom-shaders-patch/acc-lua-sdk


CHANGELOG
---------

  v1.0 - Full release
  - Cop radar gun with beam targeting + hard lock
  - Robber radar detector with real Ka/Laser audio
  - Chase system with lock/search phases
  - Ticket + Penalty panels
  - Server teleport integration (SRP/415/110)
  - Manual scoring with adjuster buttons
  - Window-gated operation, compact mode, keybinds
