// ZonesUi.cs -- the Grab Zones window. Top: the game and the gun in hand, SHOW THE SPHERES, and whether the sliders set THIS GUN
// or ALL GUNS. Then one box per zone (the magazine grab, the well, the slide / pump / bolt, the front grip): its live line ("hand 14 cm away,
// needs 12", green when the hand is inside), four sliders (forward / back, up / down, right / left, size) each with - and +
// buttons for half-centimetre steps (easier than dragging with a VR pointer), and RESET. Every change goes into zones.json at
// once; the plugin moves the zone and its sphere within a third of a second. Large type, so Window View can hang it in the headset.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

class ZonesUi : Form {
    const int POLL_MS = 250, SAVE_DEBOUNCE_MS = 60, FIND_GAME_EVERY_MS = 5000;
    const int OFFSET_MM = 300, SIZE_MIN_MM = 20, SIZE_MAX_MM = 400, NUDGE_MM = 5;
    static readonly Color Back = Color.FromArgb(28, 30, 38), Panel2 = Color.FromArgb(40, 43, 55), Ink = Color.FromArgb(235, 235, 240);
    static readonly Color Dim = Color.FromArgb(155, 160, 175), Good = Color.FromArgb(90, 200, 120), Bad = Color.FromArgb(225, 120, 95);
    static readonly Color Warn = Color.FromArgb(230, 190, 90), ButtonBack = Color.FromArgb(62, 67, 86);

    readonly Settings settings = new Settings();
    readonly ZoneFile file = new ZoneFile();
    readonly Timer poll = new Timer(), saveTimer = new Timer();
    DateTime lastFind = DateTime.MinValue, lastZonesWrite = DateTime.MinValue;
    LiveState live;
    int shownGun = -1;
    bool syncing;

    Label status;
    SkinPanel scroll;
    CheckBox show;
    RadioButton thisGun, allGuns;
    readonly List<ZoneBox> boxes = new List<ZoneBox>();
    // 2026-10-25 (Tefa: "all please"): the hand on the slide / pump / bolt (and its arc over the gun), and the gun in the right hand
    ValueBox handBox, aimBox;
    PairsBox pairsBox;   // 2026-10-25: the numbered hand pairs (PairsBox.cs)
    DateTime lastHandWrite = DateTime.MinValue;

    public ZonesUi(string gameArg) {
        Text = "Grab Zones";
        BackColor = Back; ForeColor = Ink;
        Font = new Font("Segoe UI", 11f);
        ClientSize = new Size(620, 1010);
        MinimumSize = new Size(520, 600);
        StartPosition = FormStartPosition.CenterScreen;
        string ico = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "grab_zones.ico");
        try { Icon = new Icon(ico); } catch (Exception) { }
        DoubleBuffered = true;
        Backdrop.Init(this, ico, Back);   // the icon, pixelated and faint, behind the whole window (Tefa 2026-10-25)

        scroll = new SkinPanel { Dock = DockStyle.Fill, AutoScroll = true, Padding = new Padding(8) };
        Controls.Add(scroll);
        boxes.Add(new ZoneBox(this, "mag", "GRAB THE MAGAZINE", "left grip on the seated magazine"));
        boxes.Add(new ZoneBox(this, "well", "THE WELL", "where a magazine goes back in (long guns)"));
        boxes.Add(new ZoneBox(this, "part", "SLIDE / PUMP / BOLT", "left grip on it"));
        boxes.Add(new ZoneBox(this, "grip", "FRONT GRIP", "left grip in it holds the gun two-handed: this gun's kept grip spot, moved by these sliders"));
        handBox = new ValueBox("HAND ON THE BOLT", "the left hand while it holds the slide / pump / bolt: move it, turn it, and arc it over the gun on the way", new[] {
            new ValueRow("z", "forward / back", "cm", -15, 15, 0.5), new ValueRow("y", "up / down", "cm", -15, 15, 0.5),
            new ValueRow("x", "right / left", "cm", -15, 15, 0.5), new ValueRow("rx", "tilt fingers up / down", "°", -180, 180, 1),
            new ValueRow("ry", "turn left / right", "°", -180, 180, 1), new ValueRow("rz", "roll", "°", -180, 180, 1),
            new ValueRow("arc", "arc over the gun", "cm", 0, 25, 0.5) }, () => Changed(), (t, h) => Btn(t, h));
        aimBox = new ValueBox("GUN IN THE RIGHT HAND", "where the gun points and sits in the right hand", new[] {
            new ValueRow("pitch", "aim up / down", "°", -45, 45, 1), new ValueRow("yaw", "aim left / right", "°", -45, 45, 1),
            new ValueRow("roll", "roll", "°", -45, 45, 1), new ValueRow("z", "forward / back", "cm", -10, 10, 0.5),
            new ValueRow("y", "up / down", "cm", -10, 10, 0.5), new ValueRow("x", "right / left", "cm", -10, 10, 0.5) }, () => Changed(), (t, h) => Btn(t, h));
        pairsBox = new PairsBox(file, () => Group() == "default" ? "any" : Group(), (t, h) => Btn(t, h));
        scroll.Controls.Add(pairsBox);  // docked top: added first = shown last
        scroll.Controls.Add(aimBox);
        scroll.Controls.Add(handBox);
        for (int i = boxes.Count - 1; i >= 0; i--) scroll.Controls.Add(boxes[i]);   // docked top: added last = shown first
        BuildTop();
        BuildBottom();

        string folder = gameArg ?? settings.Get("game", null);
        if (!ZoneFile.LooksLikeVillage(folder) && gameArg == null) folder = ZoneFile.FindVillage();
        if (folder != null && (gameArg != null || ZoneFile.LooksLikeVillage(folder))) UseFolder(folder, gameArg == null);

        // start at the top with nothing focused (a focused slider made the list scroll under the top bar)
        Shown += (s, e) => { ActiveControl = show; scroll.AutoScrollPosition = new Point(0, 0); };
        poll.Interval = POLL_MS; poll.Tick += (s, e) => Poll(); poll.Start();
        saveTimer.Interval = SAVE_DEBOUNCE_MS; saveTimer.Tick += (s, e) => { saveTimer.Stop(); SaveAll(); };
        Poll();
    }

    protected override void OnPaintBackground(PaintEventArgs e) { Backdrop.PaintUnder(this, e.Graphics, e.ClipRectangle); }
    protected override CreateParams CreateParams { get { return Backdrop.Composited(base.CreateParams); } }

    // ---- building -------------------------------------------------------------------------------------------------------
    internal static Button Btn(string text, EventHandler onClick, int width = 0) {
        var b = new SkinButton { Text = text, FlatStyle = FlatStyle.Flat, BackColor = ButtonBack, ForeColor = Ink, Height = 34, AutoSize = width == 0, Margin = new Padding(3) };
        b.FlatAppearance.BorderSize = 0;
        if (width > 0) b.Width = width;
        b.Click += onClick;
        return b;
    }

    static FlowLayoutPanel Row(int height) {
        return new FlowLayoutPanel { Dock = DockStyle.Top, Height = height, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, BackColor = Color.Transparent, Padding = new Padding(6, 2, 6, 0) };
    }

    void BuildTop() {
        var top = new SkinPanel { Dock = DockStyle.Top, Height = 124, Tint = Color.FromArgb(120, Back) };
        Controls.Add(top);
        status = new SkinLabel { Dock = DockStyle.Top, Height = 34, Padding = new Padding(10, 8, 0, 0), ForeColor = Dim };
        var one = Row(42);
        show = new SkinCheckBox { Text = "SHOW THE SPHERES ON THE GUN", AutoSize = true, ForeColor = Ink, BackColor = Color.Transparent, Padding = new Padding(4, 6, 12, 0) };
        show.CheckedChanged += (s, e) => { if (!syncing) SaveAll(); };
        one.Controls.Add(show);
        one.Controls.Add(Btn("GAME FOLDER...", (s, e) => PickFolder()));
        var two = Row(42);
        two.Controls.Add(new SkinLabel { Text = "the sliders set:", AutoSize = true, ForeColor = Dim, Padding = new Padding(0, 8, 6, 0) });
        thisGun = new SkinRadioButton { Text = "THIS GUN", AutoSize = true, Checked = settings.Get("scope", "gun") != "all", ForeColor = Ink, BackColor = Color.Transparent, Padding = new Padding(0, 6, 8, 0) };
        allGuns = new SkinRadioButton { Text = "ALL GUNS", AutoSize = true, Checked = settings.Get("scope", "gun") == "all", ForeColor = Ink, BackColor = Color.Transparent, Padding = new Padding(0, 6, 0, 0) };
        EventHandler scope = (s, e) => { if (((RadioButton)s).Checked) { settings.Set("scope", allGuns.Checked ? "all" : "gun"); RefreshFromFile(); } };
        thisGun.CheckedChanged += scope; allGuns.CheckedChanged += scope;
        two.Controls.Add(thisGun); two.Controls.Add(allGuns);
        top.Controls.Add(two);
        top.Controls.Add(one);
        top.Controls.Add(status);
    }

    // (2026-10-25, Tefa: "can you just have the one look and not be able to choose anything else?": the SPHERE LOOK button is
    // gone; the spheres always wear "axis", the one seen drawing. Picking "no material" had crashed the game.)

    Button forgetAll;
    DateTime forgetArmed = DateTime.MinValue;
    void BuildBottom() {
        var bottom = Row(46);
        bottom.Dock = DockStyle.Bottom;
        forgetAll = Btn("FORGET THIS GUN'S ZONES", (s, e) => ForgetGroup());
        bottom.Controls.Add(forgetAll);
        Controls.Add(bottom);
    }

    // ---- the game ---------------------------------------------------------------------------------------------------------
    void UseFolder(string folder, bool remember) {
        try { file.Use(folder); } catch (Exception ex) { status.Text = "cannot use that folder: " + ex.Message; return; }
        if (remember) settings.Set("game", folder);
        lastZonesWrite = DateTime.MinValue;
        RefreshFromFile();
        pairsBox.Reload();
    }

    void PickFolder() {
        using (var d = new FolderBrowserDialog { Description = "Pick Resident Evil Village's install folder (the one with re8.exe)" }) {
            if (d.ShowDialog(this) == DialogResult.OK) UseFolder(d.SelectedPath, true);
        }
    }

    // slide_hand.json names a gun "ri3042"; "any" = all guns (as the in-game menu)
    string HandKey() { string g = Group(); return g == "default" ? "any" : "ri" + g; }

    internal string Group() {
        if (allGuns.Checked || live == null || live.Gun <= 0) return "default";
        return live.Gun.ToString();
    }

    void Poll() {
        if (file.Folder == null) {
            if ((DateTime.Now - lastFind).TotalMilliseconds > FIND_GAME_EVERY_MS) {
                lastFind = DateTime.Now;
                string f = ZoneFile.FindVillage();
                if (f != null) UseFolder(f, true);
            }
            status.Text = "Village not found: press GAME FOLDER...";
            status.ForeColor = Bad;
            return;
        }
        bool alive = file.ScriptAlive();
        live = alive ? (file.ReadState() ?? live) : null;
        if (!alive) {
            status.Text = "Village found, but the game is not running (or the zones script is not in it)";
            status.ForeColor = Warn;
        } else if (live == null || live.Gun <= 0) {
            status.Text = "connected · no gun in hand: the sliders set ALL GUNS";
            status.ForeColor = Good;
        } else {
            status.Text = "connected · in hand: " + Program.GunName(live.Gun) + (allGuns.Checked ? " · setting ALL GUNS" : " · setting this gun");
            status.ForeColor = Good;
        }
        // the gun changed, or the in-game menu saved: show the numbers now in force (never while a save of ours is pending)
        int gun = live == null ? 0 : live.Gun;
        DateTime w = DateTime.MinValue;
        try { if (File.Exists(file.ZonesPath)) w = File.GetLastWriteTime(file.ZonesPath); } catch (IOException) { }
        DateTime hw = DateTime.MinValue;
        try { string hp = HandFile.PathIn(file); if (hp != null && File.Exists(hp)) hw = File.GetLastWriteTime(hp); } catch (IOException) { }
        if (!saveTimer.Enabled && (gun != shownGun || w != lastZonesWrite || hw != lastHandWrite)) RefreshFromFile();
        if (handBox != null) {   // named for what the gun in hand has
            string part = "BOLT";
            if (live != null) foreach (var k in new[] { "bolt", "pump", "slide" }) { var z = live.Find(k); if (z != null && z.On) { part = k.ToUpperInvariant(); break; } }
            handBox.Title = "HAND ON THE " + part;
        }
        foreach (var b in boxes) b.ShowLive(live);
        pairsBox.Poll();
        if (forgetArmed != DateTime.MinValue && (DateTime.Now - forgetArmed).TotalSeconds > 3) { forgetArmed = DateTime.MinValue; forgetAll.Text = ForgetText(); }
        else if (forgetArmed == DateTime.MinValue) forgetAll.Text = ForgetText();
    }

    string ForgetText() { return Group() == "default" ? "FORGET THE ALL-GUNS ZONES" : "FORGET THIS GUN'S ZONES"; }

    void RefreshFromFile() {
        if (file.Folder == null) return;
        try { lastZonesWrite = File.Exists(file.ZonesPath) ? File.GetLastWriteTime(file.ZonesPath) : DateTime.MinValue; } catch (IOException) { }
        shownGun = live == null ? 0 : live.Gun;
        var all = file.Load();
        syncing = true;
        show.Checked = ZoneFile.Show(all);
        foreach (var b in boxes) b.Load(all, Group(), live);
        try { string hp = HandFile.PathIn(file); lastHandWrite = hp != null && File.Exists(hp) ? File.GetLastWriteTime(hp) : DateTime.MinValue; } catch (IOException) { }
        var hands = HandFile.Load(file);
        handBox.Load(k => HandFile.Get(hands, HandKey(), k));
        aimBox.Load(k => ZoneFile.Effective(all, Group(), "aim", k));
        syncing = false;
    }

    internal void Changed() { if (!syncing) { saveTimer.Stop(); saveTimer.Start(); } }

    void SaveAll() {
        if (file.Folder == null) return;
        var all = file.Load();   // fresh: keeps what the in-game menu or another gun's numbers hold
        ZoneFile.SetShow(all, show.Checked);
        foreach (var b in boxes) b.Store(all, Group());
        if (aimBox.Touched) { ZoneFile.SetEntry(all, Group(), "aim", aimBox.Values()); aimBox.Touched = false; }
        try { file.Save(all); lastZonesWrite = File.GetLastWriteTime(file.ZonesPath); }
        catch (Exception ex) { status.Text = "could not save: " + ex.Message; status.ForeColor = Bad; }
        if (handBox.Touched) {   // the same file as the in-game menu's slide-hand sliders
            try {
                var hands = HandFile.Load(file);
                var mine = handBox.Values();
                object old;
                if (hands.TryGetValue(HandKey(), out old) && old is Dictionary<string, object>)
                    foreach (var kv in (Dictionary<string, object>)old) if (!mine.ContainsKey(kv.Key)) mine[kv.Key] = kv.Value;
                hands[HandKey()] = mine;
                HandFile.Save(file, hands);
                lastHandWrite = File.GetLastWriteTime(HandFile.PathIn(file));
                handBox.Touched = false;
            } catch (Exception ex) { status.Text = "could not save the hand: " + ex.Message; status.ForeColor = Bad; }
        }
    }

    internal void Forget(string zone) {
        if (file.Folder == null) return;
        var all = file.Load();
        ZoneFile.Forget(all, Group(), zone);
        try { file.Save(all); } catch (Exception) { }
        RefreshFromFile();
    }

    void ForgetGroup() {   // two clicks within three seconds, no pop-up (awkward inside the headset)
        if (forgetArmed == DateTime.MinValue) { forgetArmed = DateTime.Now; forgetAll.Text = "SURE? CLICK AGAIN"; return; }
        forgetArmed = DateTime.MinValue;
        var all = file.Load();
        all.Remove(Group());
        try { file.Save(all); } catch (Exception) { }
        RefreshFromFile();
    }

    // ---- one zone ---------------------------------------------------------------------------------------------------------
    class ZoneBox : Panel {
        readonly ZonesUi ui;
        readonly string slot, title;   // slot "part" = whichever the gun has (slide / pump / bolt)
        string key;
        readonly Label head, note;
        readonly Slider fwd, up, right, size;
        bool userSize;   // the size was set (this gun or the default); otherwise it shows the plugin's own

        public ZoneBox(ZonesUi ui, string slot, string title, string what) {
            this.ui = ui; this.slot = slot; this.title = title; key = slot == "part" ? "slide" : slot;
            Dock = DockStyle.Top; Height = 276; BackColor = Color.Transparent; Padding = new Padding(0, 6, 0, 6);
            var inner = new SkinPanel { Dock = DockStyle.Fill, Tint = Color.FromArgb(150, Panel2), Padding = new Padding(8, 4, 8, 4) };
            Controls.Add(inner);
            head = new SkinLabel { Dock = DockStyle.Top, Height = 28, Font = new Font("Segoe UI Semibold", 12f), ForeColor = Ink };
            note = new SkinLabel { Dock = DockStyle.Top, Height = 24, ForeColor = Dim, Text = what };
            fwd = new Slider(this, "forward / back", -OFFSET_MM, OFFSET_MM, true);
            up = new Slider(this, "up / down", -OFFSET_MM, OFFSET_MM, true);
            right = new Slider(this, "right / left", -OFFSET_MM, OFFSET_MM, true);
            size = new Slider(this, "size", SIZE_MIN_MM, SIZE_MAX_MM, false);
            var reset = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 40, BackColor = Color.Transparent, FlowDirection = FlowDirection.RightToLeft };
            reset.Controls.Add(Btn("RESET", (s, e) => ui.Forget(key)));
            foreach (Control c in new Control[] { reset, size, right, up, fwd, note, head }) inner.Controls.Add(c);
        }

        static double BuiltInCm(string k) { return k == "mag" ? 12 : k == "well" ? 16 : k == "bolt" ? 9 : k == "grip" ? 10 : 14; }

        public void Load(Dictionary<string, object> all, string group, LiveState live) {
            if (slot == "part") { var lz = PartLive(live); key = lz != null ? lz.Key : key; }
            Func<string, double> mm = a => { double v = ZoneFile.Effective(all, group, key, a); return double.IsNaN(v) ? 0 : v * 1000; };
            fwd.Set(mm("z")); up.Set(mm("y")); right.Set(mm("x"));
            double r = ZoneFile.Effective(all, group, key, "r");
            userSize = !double.IsNaN(r);
            if (userSize) size.Set(r * 1000);
            else { var lz = Live(live); size.Set((lz != null && lz.RadiusCm > 0 ? lz.RadiusCm : BuiltInCm(key)) * 10); }
        }

        public void Store(Dictionary<string, object> all, string group) {
            if (fwd.Touched || up.Touched || right.Touched) ZoneFile.SetOffset(all, group, key, right.Value / 1000.0, up.Value / 1000.0, fwd.Value / 1000.0);
            if (size.Touched || userSize) { ZoneFile.SetRadius(all, group, key, size.Value / 1000.0); userSize = true; }
            fwd.Touched = up.Touched = right.Touched = size.Touched = false;
        }

        LiveZone PartLive(LiveState live) {
            if (live == null) return null;
            foreach (var k in new[] { "bolt", "pump", "slide" }) { var z = live.Find(k); if (z != null && z.On) return z; }
            return live.Find("bolt") ?? live.Find("pump") ?? live.Find("slide");
        }
        LiveZone Live(LiveState live) { return slot == "part" ? PartLive(live) : (live == null ? null : live.Find(key)); }

        public void ShowLive(LiveState live) {
            var z = Live(live);
            string name = slot == "part" ? title.Replace("SLIDE / PUMP / BOLT", key.ToUpperInvariant()) : title;
            if (z == null || !z.On) {
                head.Text = name + (live == null ? "" : "  ·  not on this gun right now");
                head.ForeColor = Dim;
                return;
            }
            if (z.HandCm >= 0) {
                bool inside = z.HandCm <= z.RadiusCm;
                head.Text = string.Format("{0}  ·  hand {1:0} cm away, needs {2:0}", name, z.HandCm, z.RadiusCm);
                head.ForeColor = inside ? Good : Ink;
            } else {
                head.Text = string.Format("{0}  ·  size {1:0} cm", name, z.RadiusCm);
                head.ForeColor = Ink;
            }
        }

        public void Changed() { ui.Changed(); }
    }

    // a labelled slider in millimetres, shown in centimetres, with - / + buttons
    class Slider : Panel {
        readonly ZoneBox box;
        readonly FancySlider bar;
        readonly Label value;
        readonly bool signed;
        bool setting;
        public bool Touched;
        public int Value { get { return bar.Value; } }

        public Slider(ZoneBox box, string label, int min, int max, bool signed) {
            this.box = box; this.signed = signed;
            Dock = DockStyle.Top; Height = 40; BackColor = Color.Transparent;
            var name = new SkinLabel { Text = label, Dock = DockStyle.Left, Width = 128, ForeColor = Dim, Padding = new Padding(0, 8, 0, 0) };
            value = new SkinLabel { Dock = DockStyle.Right, Width = 82, ForeColor = Ink, TextAlign = ContentAlignment.MiddleRight };
            var minus = Btn("−", (s, e) => Nudge(-NUDGE_MM), 40); minus.Dock = DockStyle.Right;
            var plus = Btn("+", (s, e) => Nudge(NUDGE_MM), 40); plus.Dock = DockStyle.Right;
            minus.Font = plus.Font = new Font("Segoe UI Semibold", 13f);
            var gap = new Panel { Dock = DockStyle.Right, Width = 4, BackColor = Color.Transparent };
            bar = new FancySlider { Dock = DockStyle.Fill, Minimum = min, Maximum = max, SmallChange = 1, LargeChange = 10, Signed = signed };
            bar.ValueChanged += (s, e) => { ShowValue(); if (!setting) { Touched = true; box.Changed(); } };
            Controls.Add(bar); Controls.Add(minus); Controls.Add(gap); Controls.Add(plus); Controls.Add(value); Controls.Add(name);
            ShowValue();
        }

        void Nudge(int mm) { bar.Value = Math.Max(bar.Minimum, Math.Min(bar.Maximum, bar.Value + mm)); }

        public void Set(double mm) {
            setting = true;
            bar.Value = Math.Max(bar.Minimum, Math.Min(bar.Maximum, (int)Math.Round(mm)));
            setting = false;
            ShowValue();
        }

        void ShowValue() {
            double cm = bar.Value / 10.0;
            value.Text = (signed && cm > 0 ? "+" : "") + cm.ToString("0.0") + " cm";
        }
    }
}
