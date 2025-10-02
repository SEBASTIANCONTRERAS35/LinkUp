# Accessibility Quick Reference Card
**StadiumConnect Pro - CSC 2025 UNAM**

---

## 1-Minute Implementation Checklist

### For Every Button
```swift
Button(action: myAction) {
    // ...
}
.accessibleButton(
    label: "What it is",
    hint: "What it does",
    minTouchTarget: 44
)
.hapticFeedback(.light) // or .medium, .heavy, .warning, .success
```

### For Every Card/Complex View
```swift
VStack {
    // Multiple elements
}
.accessibleGroup(
    label: "Combined description",
    hint: "What tapping does",
    sortPriority: 8.0 // Higher = read earlier
)
```

### For Decorative Elements
```swift
Circle() // Animation, border, etc.
    .accessibilityHidden(true)
```

### For Animations
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// In .onAppear or animation modifier:
guard !reduceMotion else { return }
// ... animate
```

### For Match Scores
```swift
HStack { /* teams, scores */ }
.accessibleGroup(
    label: MatchScoreAccessibility(
        homeTeam: "México",
        awayTeam: "Canadá",
        homeScore: 0,
        awayScore: 0,
        minute: 78,
        isLive: true
    ).voiceOverLabel,
    sortPriority: 9.0
)
```

### For SOS/Emergency Actions
```swift
Button(action: sendSOS) {
    // ...
}
.accessibleButton(
    label: "Emergency SOS",
    hint: "Alerts stadium medical staff immediately",
    traits: .isEmergency
)
.hapticFeedback(.warning)
```

---

## Priority Scores (VoiceOver Navigation Order)

```
100 = Headers (read first)
90  = Emergency actions (SOS)
80  = Primary content (match, quick actions)
70  = Secondary content (location, geofence)
60  = Lists (peers, messages)
50  = Stats (battery, connections)
10  = Settings (low priority)
5   = Bottom navigation (read last)
1   = Decorative (hidden)
```

---

## Testing Commands (1-Minute Test)

### Enable VoiceOver
```
Settings > Accessibility > VoiceOver > ON
Or: Triple-click side button
```

### Basic Test
1. Open app
2. Swipe right from top to bottom
3. Verify each element announces clearly
4. No "Button" without description
5. Reading order is logical

### Dynamic Type Test
```
Settings > Accessibility > Display & Text Size > Larger Text
Drag slider to maximum
Check: No text clipping, all buttons tappable
```

### Contrast Test
```
Xcode > Open Accessibility Inspector > Audit
Check: No contrast violations
```

---

## Critical Test Cases (Must Pass)

| ID | Test | Expected | Status |
|----|------|----------|--------|
| TC-VO-01 | VoiceOver navigation | All elements announce | [ ] |
| TC-VO-02 | Match score grouping | Single announcement | [ ] |
| TC-VO-03 | SOS emergency trait | "Warning!" included | [ ] |
| TC-VO-04 | Bottom nav labels | Home/Chat/SOS labeled | [ ] |
| TC-DT-01 | Text scalability | No clipping at max size | [ ] |
| TC-TT-01 | Touch targets | All ≥44x44pt | [ ] |
| TC-HF-01 | SOS haptics | Heavy impact on tap | [ ] |

**Pass 7/7 = Ready for demo**

---

## Common Issues & Fixes

### Issue: Button reads as "Button" only
```swift
// ❌ Bad
Button(action: {}) {
    Image(systemName: "gearshape.fill")
}

// ✅ Good
Button(action: {}) {
    Image(systemName: "gearshape.fill")
}
.accessibilityLabel("Settings")
.accessibilityHint("Opens app settings")
```

### Issue: Match score reads as gibberish
```swift
// ❌ Bad (reads: "🇲🇽 MÉXICO 0 - 0 CANADÁ 🇨🇦 78 Min")
HStack {
    Text("🇲🇽"); Text("MÉXICO"); Text("0")
    Text("-")
    Text("0"); Text("CANADÁ"); Text("🇨🇦")
}

// ✅ Good (reads: "Live match: México 0, Canadá 0, at 78 minutes")
HStack { /* same content */ }
.accessibleGroup(
    label: "Live match: México 0, Canadá 0, at 78 minutes",
    hint: "Double tap for match details"
)
```

### Issue: Decorative elements announced
```swift
// ❌ Bad
Circle().fill(Color.red.opacity(0.3)) // VoiceOver reads "Circle"

// ✅ Good
Circle().fill(Color.red.opacity(0.3))
    .accessibilityHidden(true)
```

### Issue: Touch target too small
```swift
// ❌ Bad (icon is ~22pt)
Button(action: {}) {
    Image(systemName: "gearshape.fill")
        .font(.title2)
}

// ✅ Good (minimum 44pt)
Button(action: {}) {
    Image(systemName: "gearshape.fill")
        .font(.title2)
}
.frame(minWidth: 44, minHeight: 44)
```

---

## Demo Script (60 seconds)

**[0-10s]** Intro
> "StadiumConnect is accessible to EVERYONE. Watch this VoiceOver demo."

**[10-30s]** Navigate with VoiceOver
- Enable VoiceOver (triple-click)
- Swipe right 3 times (Avatar → Stats → Match)
- Show match score as single announcement
- Navigate to SOS button
- Emphasize emergency warning

**[30-45s]** Tap SOS
- Double tap SOS button
- Feel heavy haptic (mention it)
- Show confirmation screen
- "Multi-modal: visual, audio, haptic"

**[45-60s]** Summary
> "Complete VoiceOver, haptics, Dynamic Type, high contrast, reduce motion. Accessibility is our foundation. Thank you."

---

## File Locations

- **Audit:** `/ACCESSIBILITY_AUDIT.md`
- **Helpers:** `/MeshRed/Accessibility/AccessibilityModifiers.swift`
- **Guide:** `/MeshRed/Accessibility/VoiceOverGuide.md`
- **Checklist:** `/ACCESSIBILITY_TESTING_CHECKLIST.md`
- **Summary:** `/ACCESSIBILITY_IMPLEMENTATION_SUMMARY.md`
- **This file:** `/ACCESSIBILITY_QUICK_REFERENCE.md`

---

## Help Commands

### VoiceOver Gestures
- Swipe right: Next element
- Swipe left: Previous element
- Double tap: Activate
- Two-finger tap: Pause reading
- Three-finger swipe: Scroll
- Two-finger rotation: Rotor

### Xcode Shortcuts
- Cmd+R: Build and run
- Cmd+Shift+A: Open Accessibility Inspector
- Cmd+I: Run audit

### Testing Shortcuts
- Triple-click: Toggle VoiceOver
- Cmd+Shift+T: Run tests

---

## Success Criteria

✅ **Technical:**
- All buttons have labels
- Touch targets ≥44pt
- Contrast ratios ≥4.5:1
- Dynamic Type works
- VoiceOver navigation logical

✅ **Competitive:**
- Only app with emergency haptics
- Only app with semantic grouping
- Only app with custom rotors
- Only app respecting reduce motion

✅ **Demo:**
- 60-second script rehearsed
- VoiceOver demo smooth
- Judges' questions answered

---

**Print This Card → Keep During Implementation**

---

**Version:** 1.0 | **Date:** October 1, 2025 | **CSC 2025 UNAM**
