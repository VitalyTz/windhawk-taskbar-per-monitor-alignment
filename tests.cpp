#include "taskbar-per-monitor-alignment.wh.cpp"
#include <cassert>

// The icon alignment chosen for a monitor, the part of the placement most tests look at.
static int SelectAlignment(const Settings& settings, const MonitorIdentity& monitor, bool primary) {
    return SelectPlacement(settings, monitor, primary).icons;
}
#include <cstdio>

MonitorIdentity Primary() {
    return {L"DISPLAY1", L"DELL U2719D", L"\\\\?\\DISPLAY#DELA0C1#5&1234ABCD&0&UID4353"};
}
MonitorIdentity Secondary() {
    return {L"DISPLAY2", L"ACER XV272U", L"\\\\?\\DISPLAY#ACR0629#5&1234ABCD&0&UID4354"};
}

int main() {
    Settings s;
    s.primary = 1; s.secondary = 0;
    // Defaults by primary status when no rule matches.
    assert(SelectAlignment(s, Primary(), true) == 1);
    assert(SelectAlignment(s, Secondary(), false) == 0);
    assert(SelectAlignment(Settings{}, Secondary(), false) == -1);

    // Device names: short/long form, case, surrounding spaces, no prefix match.
    s.monitors = {{L"display2", 1}, {L"DISPLAY2", 0}, {L"", 0}};
    assert(SelectAlignment(s, Secondary(), false) == 1);  // First rule wins.
    s.monitors = {{L"  \\\\.\\display2 ", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 1);
    assert(SelectAlignment(s, Primary(), true) == 1);  // Primary default, rule unmatched.
    s.monitors = {{L"DISPLAY20", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 0);

    // An explicit Windows default beats the primary/secondary default.
    s.monitors = {{L"\\\\.\\DISPLAY1", -1}};
    assert(SelectAlignment(s, Primary(), true) == -1);

    // Friendly names match in full only.
    s.monitors = {{L"acer xv272u", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 1);
    assert(SelectAlignment(s, Primary(), true) == 1);  // Primary default, not the rule.
    s.monitors = {{L"ACER", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 0);  // No partial friendly match.

    // Device paths match as a substring, but only for rules containing '#'.
    s.monitors = {{L"display#acr0629", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 1);
    s.monitors = {{L"UID4354", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 0);
    s.monitors = {{L"#UID4354", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 0);  // Not a path substring.
    s.monitors = {{L"&0&UID4354", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 0);  // Needs '#' to match loosely.

    // Rules without identifiers are ignored and an empty identity never matches.
    s.monitors = {{L"   ", 1}};
    assert(SelectAlignment(s, Secondary(), false) == 0);
    s.monitors = {{L"DISPLAY1", 1}};
    assert(SelectAlignment(s, MonitorIdentity{}, false) == 0);

    // Right is this mod's own value and travels through the same rules.
    s.monitors = {{L"DISPLAY2", kRight}};
    assert(SelectAlignment(s, Secondary(), false) == kRight);
    assert(SelectAlignment(s, Primary(), true) == kCenter);
    assert(SelectAlignment(Settings{kRight, kLeft, {}, false}, Primary(), true) == kRight);

    // Without the FrameHeight symbol the element offset is unknown, and right
    // alignment stays off rather than guessing at the layout.
    assert(TaskbarElementOffset() == 0);
    const BYTE frameHeight[] = {0x48, 0x83, 0xEC, 0x28, 0x48, 0x83, 0xC1, 0x10};
    g_frameHeight = (void*)frameHeight;
    assert(TaskbarElementOffset() == 0x10);
    const BYTE unexpected[] = {0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90};
    g_frameHeight = (void*)unexpected;
    assert(TaskbarElementOffset() == 0);
    g_frameHeight = nullptr;
    assert(TaskbarElementFromSite(nullptr) == nullptr);
    RequestLayout(nullptr, true, kFollowIcons);  // No registered message: no-op.

    // Position rules: monitors named by where they sit from the left, not by id.
    MonitorIdentity first = Primary(), second = Secondary();
    first.position = 0; first.count = 3;
    second.position = 1; second.count = 3;
    MonitorIdentity third = Secondary();
    third.position = 2; third.count = 3;
    MonitorRule rule2nd{L"", kRight, kFollowIcons, 1};
    assert(!RuleMatches(rule2nd, first) && RuleMatches(rule2nd, second) && !RuleMatches(rule2nd, third));
    MonitorRule last{L"", kLeft, kFollowIcons, kPositionLast};
    assert(!RuleMatches(last, second) && RuleMatches(last, third));
    assert(!RuleMatches(rule2nd, Primary()));  // Position unknown: never matches.
    MonitorRule typed{L"display2", kLeft};
    assert(RuleMatches(typed, Secondary()) && !RuleMatches(typed, Primary()));
    s.monitors = {rule2nd, MonitorRule{L"", kCenter, kFollowIcons, 0}};
    assert(SelectAlignment(s, second, false) == kRight);
    assert(SelectAlignment(s, first, true) == kCenter);
    assert(SelectAlignment(s, third, false) == s.secondary);  // No rule: the default.

    // Start button placement: per rule, per primary/secondary, and resolved
    // against where the icons are.
    Settings st;
    st.primary = kCenter; st.secondary = kLeft;
    st.primaryStart = kLeft; st.secondaryStart = kRight;
    assert(SelectPlacement(st, Primary(), true).start == kLeft);
    assert(SelectPlacement(st, Secondary(), false).start == kRight);
    st.monitors = {MonitorRule{L"DISPLAY2", kCenter, kLeft}};
    assert(SelectPlacement(st, Secondary(), false).icons == kCenter);
    assert(SelectPlacement(st, Secondary(), false).start == kLeft);
    assert(ResolveStartMode(kFollowIcons, kCenter) == kFollowIcons);
    assert(ResolveStartMode(kLeft, kLeft) == kFollowIcons);   // Already where the icons are.
    assert(ResolveStartMode(kLeft, kCenter) == kLeft);
    assert(ResolveStartMode(kRight, kLeft) == kRight);
    assert(ResolveStartMode(kRight, kRight) == kFollowIcons);

    // The layout request packs both choices into a window message parameter.
    for (bool right : {false, true})
        for (int start = kFollowIcons; start <= kRight; ++start) {
            const int packed = PackLayout(right, start);
            assert(LayoutWantsRight(packed) == right && LayoutStartMode(packed) == start);
        }
    assert(PackLayout(false, kFollowIcons) == 0);  // "Nothing to change" is zero.

    assert(NormalizeIdentifier(L"\\\\.\\display12") == L"DISPLAY12");
    assert(NormalizeIdentifier(L" \\\\?\\display#x ") == L"\\\\?\\DISPLAY#X");
    assert(NormalizeIdentifier(L"  ").empty());

    // Only device-name rules avoid the display configuration lookup.
    assert(LooksLikeDeviceName(L"\\\\.\\display3"));
    assert(!LooksLikeDeviceName(L"DISPLAY"));
    assert(!LooksLikeDeviceName(L"DISPLAY#DELA0C1"));
    assert(!LooksLikeDeviceName(L"DELL U2719D"));

    void* object[32]{};
    int fakeVtable = 0;
    assert(FindSettingsInterface(object) == nullptr);  // No vtable symbol: no guess.
    g_settingsInterfaceVtable = &fakeVtable;
    object[7] = &fakeVtable;
    assert(FindSettingsInterface(object) == &object[7]);
    object[7] = nullptr;
    assert(FindSettingsInterface(object) == nullptr);
    assert(FindSettingsInterface(nullptr) == nullptr);

    assert(OverrideAlignment(object, 1) == 1);  // Untracked taskbar: preserve Windows.
    g_taskbars[object] = {nullptr, nullptr};
    assert(OverrideAlignment(object, 0) == 0);  // No site, no window: preserve Windows.
    g_taskbars[object] = {nullptr, reinterpret_cast<HWND>(object)};
    assert(OverrideAlignment(object, 1) == 1);  // Invalid HWND: preserve Windows.
    assert(g_taskbars[object].hwnd == nullptr);  // And the stale HWND is dropped.
    g_unloading = true;
    assert(OverrideAlignment(object, 1) == 1);

    // Live check of the display-configuration lookup. Skipped where no active
    // display path is reported, for example a session without a desktop.
    RebuildDisplayNames();
    for (const auto& [device, names] : g_displayNames) {
        wprintf(L"  %ls -> friendly '%ls' path '%ls'\n", device.c_str(),
                names.friendly.c_str(), names.path.c_str());
        assert(!names.friendly.empty() || !names.path.empty());
        MonitorIdentity identity{device, names.friendly, names.path};
        Settings live;
        live.monitors = {{names.friendly, 1}};
        if (!names.friendly.empty()) assert(SelectAlignment(live, identity, false) == 1);
        live.monitors = {{names.path, 0}};
        if (!names.path.empty()) assert(SelectAlignment(live, identity, true) == 0);
    }
    if (g_displayNames.empty()) puts("  (no active display paths; lookup not exercised)");

    puts("PASS: defaults, monitor matching (identifier and position), Start placement, "
         "Windows-default override, interface lookup, and untracked-taskbar fallback.");
}
