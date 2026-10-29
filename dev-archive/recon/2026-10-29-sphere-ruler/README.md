# 2026-10-29 — a ruler for the drawn zone spheres (flat desk run)

Question: do the grip-zone spheres draw as big as their numbers say? The model's own box said half 0.030 m; the drawn ball
looked huge on the flat screen.

Method: camera position and FOV from the RE Engine MCP (`reframework_get_camera`: 50.651, -18.239, -1.017; FOV 51.32 deg,
vertical), the sphere's position and scale from the zones log (`part SHOWN r 0.14 at 50.83 -18.32 -1.44 scale 4.700`), a
screenshot of the game window (1920 x 1421). Distance camera to sphere 0.466 m. The ball's outline read by eye (apex y 568
at x 1290, leftmost x 757): radius 530 px. Focal length 1421/2 / tan(25.66 deg) = 1479 px, so tan(theta) = 0.358,
sin(theta) = 0.337, drawn radius 0.466 x 0.337 = 0.157 m; divided by the scale 4.70: the model's half is 0.033 m.

Answer: the box (0.030) is right within the ruler's error (about 10 %); the drawn size follows the number. The old
measuring (world box divided by the scale, which lags) was what made the spheres 3.5x too small on 10-25.
`ball_fit.py` tried a least-squares circle on the outline and kept too few points (the scene behind is busy); the hand
reading above is the one used. `ball_measure.py` finds the red checker's extent on the centre row/column.
