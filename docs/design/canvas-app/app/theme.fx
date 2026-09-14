// ============================================================================
// theme.fx — design tokens for the Quality Management app
// Paste into App.OnStart (or a "cmpTheme" component's OnReset) BEFORE the
// startup logic in App.OnStart.fx. Every screen references gTheme.* so the
// look is consistent and changeable in one place.
//
// Design language: clean, high-contrast, industrial. Deep teal primary (quality
// / inspection), amber for "attention/fail", green for pass. Generous 8px-grid
// spacing, one accent per screen. Reference screenshots in the manual are NOT
// copied — this is the redesign.
// ============================================================================

Set(
    gTheme,
    {
        // ---- Brand palette ----
        Primary:      RGBA(0, 95, 115, 1),      // deep teal — headers, primary buttons
        PrimaryDark:  RGBA(0, 63, 77, 1),       // pressed / status bar
        PrimaryTint:  RGBA(224, 240, 242, 1),   // selected rows, chips
        Accent:       RGBA(238, 155, 0, 1),     // amber — CTAs, highlights

        // ---- Semantic ----
        Pass:         RGBA(45, 138, 62, 1),     // test pass / available batch
        Fail:         RGBA(199, 62, 45, 1),     // test fail / blocked
        Warn:         RGBA(238, 155, 0, 1),
        Info:         RGBA(0, 119, 182, 1),

        // ---- Neutrals ----
        Bg:           RGBA(247, 249, 250, 1),   // app background
        Surface:      RGBA(255, 255, 255, 1),   // cards, fields
        Border:       RGBA(214, 221, 224, 1),
        Ink:          RGBA(23, 33, 38, 1),      // primary text
        InkSoft:      RGBA(90, 103, 110, 1),    // secondary text
        OnPrimary:    RGBA(255, 255, 255, 1),
        Disabled:     RGBA(180, 190, 194, 1),

        // ---- Spacing (8px grid) ----
        S1: 4, S2: 8, S3: 12, S4: 16, S5: 24, S6: 32, S7: 48,

        // ---- Radius / elevation ----
        Radius: 12,
        RadiusSm: 8,
        CardShadow: RGBA(0, 0, 0, 0.08),

        // ---- Type scale ----
        FontFamily: Font.'Open Sans',
        SizeDisplay: 28,
        SizeTitle:   22,
        SizeH2:      18,
        SizeBody:    15,
        SizeLabel:   13,
        SizeCaption: 11
    }
);

// Convenience: the 4 home functions and their icons/colors, driven as data so
// scrHome renders tiles from a gallery instead of 4 hand-placed buttons.
ClearCollect(
    colHomeTiles,
    { key: "QO", title: "Quality Order",          sub: "Create a quality order",        icon: Icon.DocumentPDF,   color: gTheme.Primary, target: "scrQOMenu" },
    { key: "TR", title: "Enter Test Results",     sub: "Record test outcomes",          icon: Icon.CheckBadge,    color: gTheme.Info,    target: "scrTRMenu" },
    { key: "NC", title: "Create NC",              sub: "Raise a non-conformance",       icon: Icon.Warning,       color: gTheme.Accent,  target: "scrNCMenu" },
    { key: "BD", title: "Manage Batch Disposition", sub: "Scan & change batch code",    icon: Icon.BarcodeScan,   color: gTheme.Pass,    target: "scrBDScan" }
);
