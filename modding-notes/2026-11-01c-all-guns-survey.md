# All-guns survey, 2026-11-01 13:1x (simulator, build with the revolver handle under the grip)

Per gun: the zones it has; per zone: the sphere shown when its Grip Zones row is open, the left hand walked in (the game's own hand distance), LG pressed, what took the hand. Tool: dev-archive/native/tools/sim/survey.py. "NO pose line" = the Hand Poser log line stops after 50 loads, not a failure.

```
== LEMI: pose loaded; zones ['mag', 'well', 'slide', 'slide-left']
   mag        sphere SHOWN; best 0.3 cm at left [0.14, 1.415, -0.365, 0, 0]; LG: reload: the left hand on the seated magazine (0.082 m from it): right B releases it into the hand
   well       sphere SHOWN; best 0.3 cm at left [0.09, 1.445, -0.445, 0, 0]; LG: rack: slide taken in its right-side sphere
   slide      sphere SHOWN; best 0.5 cm at left [0.02, 1.43, -0.44, 0, 0]; LG: rack: slide taken in its right-side sphere
   slide-left sphere SHOWN; best 0.2 cm at left [0.02, 1.445, -0.49, 0, 0]; LG: rack: slide taken in its left-side sphere
== M1911: pose loaded; zones ['mag', 'well', 'slide', 'slide-left']
   mag        sphere SHOWN; best 0.1 cm at left [0.095, 1.45, -0.445, 0, 0]; LG: reload: the left hand on the seated magazine (0.080 m from it): right B releases it into the hand
   well       sphere SHOWN; best 0.3 cm at left [0.1, 1.445, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.072 m from it): right B releases it into the hand
   slide      sphere SHOWN; best 0.3 cm at left [0.04, 1.475, -0.435, 0, 0]; LG: rack: slide taken in its right-side sphere
   slide-left sphere SHOWN; best 0.5 cm at left [0.005, 1.45, -0.49, 0, 0]; LG: rack: slide taken in its left-side sphere
== V61: pose loaded; zones ['mag', 'well', 'slide', 'slide-left']
   mag        sphere SHOWN; best 0.3 cm at left [0.1, 1.45, -0.445, 0, 0]; LG: reload: the left hand on the seated magazine (0.082 m from it): right B releases it into the hand
   well       sphere SHOWN; best 0.8 cm at left [0.04, 1.36, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.097 m from it): right B releases it into the hand
   slide      sphere SHOWN; best 0.5 cm at left [-0.06, 1.38, -0.44, 0, 0]; LG: rack: slide taken in its right-side sphere
   slide-left sphere SHOWN; best 0.3 cm at left [-0.065, 1.39, -0.49, 0, 0]; LG: rack: slide taken in its left-side sphere
== USM-AI: pose loaded; zones ['mag', 'well', 'slide', 'slide-left']
   mag        sphere SHOWN; best 0.2 cm at left [0.1, 1.45, -0.445, 0, 0]; LG: reload: the left hand on the seated magazine (0.081 m from it): right B releases it into the hand
   well       sphere SHOWN; best 0.5 cm at left [0.1, 1.44, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.072 m from it): right B releases it into the hand
   slide      sphere SHOWN; best 0.5 cm at left [0.03, 1.46, -0.44, 0, 0]; LG: rack: slide taken in its right-side sphere
   slide-left sphere SHOWN; best 0.2 cm at left [0.03, 1.47, -0.485, 0, 0]; LG: rack: slide taken in its left-side sphere
== S.T.A.K.E: pose loaded; zones ['mag', 'well', 'slide', 'slide-left']
   mag        sphere SHOWN; best 0.4 cm at left [0.09, 1.46, -0.44, 0, 0]; LG: reload: the left hand on the seated magazine (0.084 m from it): right B releases it into the hand
   well       sphere SHOWN; best 0.2 cm at left [0.11, 1.445, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.060 m from it): right B releases it into the hand
   slide      sphere SHOWN; best 0.3 cm at left [0.08, 1.52, -0.43, 0, 0]; LG: rack: slide taken in its right-side sphere
   slide-left sphere SHOWN; best 0.5 cm at left [0.04, 1.485, -0.48, 0, 0]; LG: rack: slide taken in its left-side sphere
== Rocket Pistol: pose loaded; zones []
== Samurai Edge: pose loaded; zones ['mag', 'well', 'slide', 'slide-left']
   mag        sphere SHOWN; best 0.1 cm at left [0.095, 1.45, -0.445, 0, 0]; LG: reload: the left hand on the seated magazine (0.080 m from it): right B releases it into the hand
   well       sphere SHOWN; best 0.3 cm at left [0.1, 1.445, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.072 m from it): right B releases it into the hand
   slide      sphere SHOWN; best 0.3 cm at left [0.04, 1.475, -0.435, 0, 0]; LG: rack: slide taken in its right-side sphere
   slide-left sphere SHOWN; best 0.5 cm at left [0.005, 1.45, -0.49, 0, 0]; LG: rack: slide taken in its left-side sphere
== M1851: NO pose line; zones ['handle', 'drum']
   handle     sphere SHOWN; best 0.6 cm at left [0.28, 1.37, -0.49, 0, 0]; LG: pairs: LG at the handle: the left hand docks there
   drum       sphere SHOWN; best 0.5 cm at left [0.12, 1.42, -0.47, 0, 0]; LG: (felt) pairs: LG at the drum: the left hand docks there
== Handcannon: NO pose line; zones ['handle', 'drum']
   handle     sphere SHOWN; best 0.7 cm at left [0.27, 1.36, -0.49, 0, 0]; LG: (felt) pairs: LG at the handle: the left hand docks there
   drum       sphere SHOWN; best 0.4 cm at left [0.12, 1.42, -0.47, 0, 0]; LG: (felt) pairs: LG at the drum: the left hand docks there
== W870: NO pose line; zones ['well', 'pump']
   well       sphere SHOWN; best 0.4 cm at left [-0.14, 1.32, -0.48, 0, 0]; LG: rack: left hand 0.169 m from the pump joint (need 0.14, the controller): too far
   pump       sphere SHOWN; best 0.3 cm at left [-0.27, 1.21, -0.5, 0, 0]; LG: rack: left hand 0.003 m from the pump joint (need 0.14, the controller): HAND ON
== M1897: NO pose line; zones ['well', 'pump']
   well       sphere SHOWN; best 0.2 cm at left [-0.105, 1.385, -0.495, 0, 0]; LG: rack: left hand 0.242 m from the pump joint (need 0.10, the controller): too far
   pump       sphere SHOWN; best 0.4 cm at left [-0.31, 1.28, -0.56, 0, 0]; LG: rack: left hand 0.004 m from the pump joint (need 0.10, the controller): HAND ON
== F2: NO pose line; zones ['mag', 'well', 'bolt', 'grip']
   mag        sphere SHOWN; best 0.8 cm at left [0.12, 1.38, -0.47, 0, 0]; LG: reload: the left hand on the seated magazine (0.009 m from it): LT pulls it out
   well       sphere SHOWN; best 4.6 cm at left [0.0, 1.26, -0.45, 0, 0]; LG: nothing took the hand
   bolt       sphere SHOWN; best 1.0 cm at left [0.06, 1.43, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.082 m from it): LT pulls it out
   grip       sphere SHOWN; best 1.3 cm at left [-0.08, 1.18, -0.45, 0, 0]; LG: nothing took the hand
== WCX: NO pose line; zones ['mag', 'well', 'slide']
   mag        sphere SHOWN; best 0.3 cm at left [0.1, 1.46, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.082 m from it): LT pulls it out
   well       sphere SHOWN; best 0.5 cm at left [0.0, 1.38, -0.47, 0, 0]; LG: rack: left hand 0.185 m from the slide joint (need 0.14, the controller): too far
   slide      sphere SHOWN; best 0.3 cm at left [0.04, 1.56, -0.435, 0, 0]; LG: rack: left hand 0.003 m from the slide joint (need 0.14, the controller): HAND ON
== Dragoon: NO pose line; zones ['mag', 'well', 'slide']
   mag        sphere SHOWN; best 0.3 cm at left [0.1, 1.46, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.082 m from it): LT pulls it out
   well       sphere SHOWN; best 0.4 cm at left [0.0, 1.33, -0.475, 0, 0]; LG: rack: left hand 0.121 m from the slide joint (need 0.14, the controller): HAND ON
   slide      sphere SHOWN; best 0.4 cm at left [-0.1, 1.4, -0.495, 0, 0]; LG: rack: left hand 0.003 m from the slide joint (need 0.14, the controller): HAND ON
== SYG-12: NO pose line; zones ['mag', 'well', 'slide']
   mag        sphere SHOWN; best 0.4 cm at left [0.1, 1.46, -0.45, 0, 0]; LG: reload: the left hand on the seated magazine (0.077 m from it): LT pulls it out
   well       sphere SHOWN; best 0.3 cm at left [-0.06, 1.385, -0.47, 0, 0]; LG: rack: left hand 0.045 m from the slide joint (need 0.14, the controller): HAND ON
   slide      sphere SHOWN; best 0.7 cm at left [-0.1, 1.4, -0.47, 0, 0]; LG: rack: left hand 0.007 m from the slide joint (need 0.14, the controller): HAND ON
== GM 79: NO pose line; zones ['insert']
   insert     sphere SHOWN; best 3.5 cm at left [0.12, 1.42, -0.45, 0, 0]; LG: (felt) pairs: LG at the insert point: the left hand docks there
done
```
