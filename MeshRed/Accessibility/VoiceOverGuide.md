# VoiceOver Navigation Guide
**StadiumConnect Pro - CSC 2025 UNAM**

This document provides step-by-step VoiceOver navigation flows for all major views in StadiumConnect Pro, designed for accessibility testing and demo preparation.

---

## Table of Contents
1. [StadiumDashboardView Navigation](#1-stadiumdashboardview-navigation)
2. [ImprovedHomeView Navigation](#2-improvedhomeview-navigation)
3. [SOSView Navigation](#3-sosview-navigation)
4. [Navigation Between Views](#4-navigation-between-views)
5. [Common Gestures](#5-common-voiceover-gestures)
6. [Demo Script (60 seconds)](#6-demo-script-60-seconds)

---

## 1. StadiumDashboardView Navigation

### Logical Reading Order

```
1. Header Group (sortPriority: 10)
   ├─ Stadium name & section
   └─ Settings button

2. Match Score Card (sortPriority: 9)
   └─ Single grouped element with complete match info

3. Feature Grid (sortPriority: 8)
   ├─ Tu Red card
   ├─ Ubicaciones card
   └─ Perimetros card

4. Bottom Navigation (sortPriority: 5)
   ├─ Home button
   ├─ Chat button
   └─ SOS button (emergency trait)
```

### Step-by-Step VoiceOver Flow

**Starting from top:**

1. **Stadium Header** (Swipe Right)
   - **Hears:** "Estadio Azteca, Sección 4B, heading"
   - **Action:** None (informational)

2. **Settings Button** (Swipe Right)
   - **Hears:** "Settings button, opens app settings and preferences"
   - **Action:** Double tap to open settings sheet

3. **Match Score Card** (Swipe Right)
   - **Hears:** "Live match: México 0, Canadá 0, at 78 minutes. México leading in possession. Button. Double tap to view full match details."
   - **Action:** Double tap opens match details (future implementation)
   - **Note:** This is a single grouped element combining flag emojis, team names, scores, and time

4. **Tu Red Feature Card** (Swipe Right)
   - **Hears:** "Tu Red, 3 connected. Button. Double tap to view network connections and manage devices."
   - **Action:** Double tap opens network view
   - **Haptic:** Light impact on tap

5. **Ubicaciones Feature Card** (Swipe Right)
   - **Hears:** "Ubicaciones, Share your location with family. Button. Double tap to access location sharing and LinkFinder navigation."
   - **Action:** Double tap opens location view
   - **Haptic:** Light impact on tap

6. **Perimetros Feature Card** (Swipe Right)
   - **Hears:** "Perimetros, Stadium zones and linkfencing. Button. Double tap to view linkfence map and zones."
   - **Action:** Double tap opens linkfence map
   - **Haptic:** Light impact on tap

7. **Home Navigation Button** (Swipe Right)
   - **Hears:** "Home button, selected"
   - **Action:** Already on home (no-op)
   - **Haptic:** Medium impact on tap

8. **Chat Navigation Button** (Swipe Right)
   - **Hears:** "Chat button, opens messaging dashboard"
   - **Action:** Double tap switches to chat view
   - **Haptic:** Medium impact on tap

9. **SOS Navigation Button** (Swipe Right)
   - **Hears:** "Emergency SOS button, sends urgent alerts to stadium staff. Warning!"
   - **Action:** Double tap switches to emergency view
   - **Haptic:** Heavy impact on tap
   - **Trait:** Emergency (high priority)

**End of view**

---

## 2. ImprovedHomeView Navigation

### Logical Reading Order

```
1. Header Group (sortPriority: 10)
   ├─ User avatar with online status
   ├─ Stadium & section info
   ├─ Network status badge
   └─ Settings button

2. Quick Stats Bar (sortPriority: 9)
   ├─ Family stat (grouped)
   ├─ Messages stat (grouped)
   └─ Connected stat (grouped)

3. Match Card (sortPriority: 8)
   ├─ Live indicator (decorative, hidden)
   └─ Match score (grouped)

4. Match Stats (sortPriority: 7)
   ├─ Possession stat (grouped)
   └─ Shots stat (grouped)

5. Feature Grid Section (sortPriority: 6)
   ├─ Section heading
   └─ 4 feature cards

6. Nearby Services Section (sortPriority: 5)
   ├─ Section heading
   └─ 3 service rows
```

### Step-by-Step VoiceOver Flow

**Starting from top:**

1. **User Avatar** (Swipe Right)
   - **Hears:** "Your profile, online. Button. Double tap to view profile settings."
   - **Visual:** Green online indicator announced

2. **Stadium Location** (Swipe Right)
   - **Hears:** "Estadio Azteca, Sección 4B, heading"

3. **Network Status Badge** (Swipe Right)
   - **Hears:** "Network status: 3 devices connected. Signal strength excellent."
   - **Action:** Double tap for network details

4. **Settings Button** (Swipe Right)
   - **Hears:** "Settings button"
   - **Touch Target:** 44x44pt minimum

5. **Family Quick Stat** (Swipe Right)
   - **Hears:** "Family, 4 members. Statistic."
   - **Grouped:** Icon + value + label as single element

6. **Messages Quick Stat** (Swipe Right)
   - **Hears:** "Messages, 0 unread. Statistic."

7. **Connected Quick Stat** (Swipe Right)
   - **Hears:** "Connected, 3 devices. Statistic."

8. **Match Score Card** (Swipe Right)
   - **Hears:** "Live match: México 0, Canadá 0, at 78 minutes. Button. Double tap for match details."
   - **Note:** Pulsing "EN VIVO" indicator hidden as decorative
   - **Animation:** Skipped if Reduce Motion enabled

9. **Possession Stat** (Swipe Right)
   - **Hears:** "Possession: México 58 percent, Canadá 42 percent. Statistic."

10. **Shots Stat** (Swipe Right)
    - **Hears:** "Shots on goal: México 12, Canadá 8. Statistic."

11. **Funciones Rápidas Heading** (Swipe Right)
    - **Hears:** "Funciones Rápidas, heading"

12. **Tu Red Card** (Swipe Right)
    - **Hears:** "Tu Red, 3 connected. Button. Double tap to view network."
    - **Haptic:** Light impact

13. **Familia Card** (Swipe Right)
    - **Hears:** "Familia, 4 miembros. Button. Double tap to manage family group."
    - **Haptic:** Light impact

14. **Ubicación Card** (Swipe Right)
    - **Hears:** "Ubicación, Comparte tu posición. Button. Double tap to share location."
    - **Haptic:** Light impact

15. **LinkFencing Card** (Swipe Right)
    - **Hears:** "LinkFencing, Zonas del estadio. Button. Double tap to view stadium zones."
    - **Haptic:** Light impact

16. **Servicios Cercanos Heading** (Swipe Right)
    - **Hears:** "Servicios Cercanos, heading"

17. **Baños Service Row** (Swipe Right)
    - **Hears:** "Baños, 50 meters, Disponible. Button. Double tap for navigation."

18. **Concesiones Service Row** (Swipe Right)
    - **Hears:** "Concesiones, 120 meters, Ocupado. Button. Double tap for navigation."

19. **Tienda Oficial Service Row** (Swipe Right)
    - **Hears:** "Tienda Oficial, 200 meters, Disponible. Button. Double tap for navigation."

**End of scrollable content**

---

## 3. SOSView Navigation

### Logical Reading Order

```
1. Central SOS Button (sortPriority: 10)
   └─ Emergency medical alert (highest priority)

2. SOS Type Grid (sortPriority: 8)
   ├─ Asistencia card
   ├─ Me Perdí card
   └─ Seguridad card

3. Header Time (sortPriority: 1)
   └─ Decorative, low priority
```

### Step-by-Step VoiceOver Flow

**Starting from top:**

1. **Central SOS Button** (Swipe Right)
   - **Hears:** "Emergency SOS, Emergencia Médica. Button. Double tap to send urgent medical emergency alert to nearby stadium staff and connected devices. This is a high priority emergency request. Warning!"
   - **Action:** Double tap opens confirmation sheet
   - **Haptic:** Heavy impact (warning style)
   - **Animation:** Pulsing rings hidden as decorative
   - **Trait:** Emergency + isButton

2. **Asistencia Card** (Swipe Right)
   - **Hears:** "Asistencia, Necesito ayuda o información. Button. Double tap to request general assistance."
   - **Action:** Opens confirmation sheet
   - **Haptic:** Light impact
   - **Color:** Blue (Mundial2026Colors.azul)

3. **Me Perdí Card** (Swipe Right)
   - **Hears:** "Me Perdí, No encuentro a mi grupo. Button. Double tap to alert family that you are separated."
   - **Action:** Opens confirmation sheet
   - **Haptic:** Light impact
   - **Color:** Green (Mundial2026Colors.verde)

4. **Seguridad Card** (Swipe Right)
   - **Hears:** "Seguridad, Situación de riesgo o peligro. Button. Double tap to report security concern."
   - **Action:** Opens confirmation sheet
   - **Haptic:** Medium impact
   - **Color:** Orange

5. **Time Display** (Last, if at all)
   - **Hears:** "12:00"
   - **Note:** Low priority, informational only

**End of main view**

### SOS Confirmation Sheet Flow

**After tapping any SOS type:**

1. **Cancel Button** (Toolbar)
   - **Hears:** "Cancel button, closes alert without sending"
   - **Action:** Dismisses sheet

2. **Alert Icon** (Swipe Right)
   - **Hears:** "[Type] emergency icon, decorative"
   - **Hidden:** Should be marked decorative

3. **Alert Title** (Swipe Right)
   - **Hears:** "[Type], heading"

4. **Alert Description** (Swipe Right)
   - **Hears:** "[Full description text]"

5. **Message Field Label** (Swipe Right)
   - **Hears:** "Mensaje adicional opcional, heading"

6. **TextEditor** (Swipe Right)
   - **Hears:** "Additional message text field, editable text. Double tap to edit."
   - **Action:** Opens keyboard
   - **Note:** Should announce character count if limited

7. **Device Count Info** (Swipe Right)
   - **Hears:** "3 dispositivos recibirán la alerta"
   - **Trait:** Static text

8. **Confirm Button** (Swipe Right)
   - **Hears:** "Enviar Alerta SOS button. Double tap to confirm and broadcast emergency alert. This will notify stadium medical staff and your family group."
   - **Action:** Sends alert, announces confirmation, dismisses
   - **Haptic:** Heavy impact (warning)
   - **Announcement:** "Emergency alert sent successfully. Stadium staff has been notified."

**End of confirmation sheet**

---

## 4. Navigation Between Views

### Bottom Navigation Bar

The bottom navigation bar is **persistent across all views** and should maintain focus context.

**Tab Navigation Flow:**

1. **Current Tab Indicator**
   - Selected tab has `.accessibilityAddTraits(.isSelected)`
   - Announces "selected" when focused

2. **Switching Tabs**
   - **Home:** "Home button, shows stadium dashboard and match info"
   - **Chat:** "Chat button, opens messaging with connected devices"
   - **SOS:** "Emergency SOS button, sends urgent alerts. Warning!"

3. **Haptic Patterns**
   - Home: Medium impact
   - Chat: Medium impact
   - SOS: Heavy impact + warning notification

**Best Practice:**
- After switching tabs, VoiceOver should focus on first meaningful element
- Bottom bar remains last in swipe order (sortPriority: 1)

---

## 5. Common VoiceOver Gestures

### Basic Navigation
- **Swipe Right:** Next element
- **Swipe Left:** Previous element
- **Double Tap:** Activate button/link
- **Two-Finger Tap:** Pause/resume reading
- **Three-Finger Swipe Right:** Next page (scroll)
- **Three-Finger Swipe Left:** Previous page (scroll)

### Advanced Navigation
- **Rotor (Two-Finger Rotation):** Access custom navigation modes
  - Headings mode: Jump between sections
  - Buttons mode: Jump between interactive elements
  - Forms mode: Jump between text fields (in SOS confirmation)
  - Landmarks mode: Jump to major sections

### Custom Rotors for StadiumConnect
- **Peers Rotor:** Navigate between connected devices
- **Messages Rotor:** Navigate between conversations
- **Zones Rotor:** Navigate between linkfence zones
- **Services Rotor:** Navigate between nearby services

### Reading Controls
- **Magic Tap (Two-Finger Double Tap):** Quick action (SOS send)
- **Swipe Up/Down:** Depends on rotor setting
- **Three-Finger Triple Tap:** Screen curtain toggle

---

## 6. Demo Script (60 seconds)

**For CSC 2025 Presentation**

### Setup
- iPhone with VoiceOver enabled
- StadiumConnect app open on Home view
- 2-3 devices connected to LinkLinkMesh network
- Family group configured

### Script (Timed)

**[0:00-0:10] Introduction**
> "StadiumConnect Pro is designed for EVERYONE, including people with visual impairments. Let me demonstrate our VoiceOver experience."

**[0:10-0:20] Home Navigation**
- **Swipe:** Avatar → Stats → Match Score
> VoiceOver announces: "Live match: México 0, Canadá 0, at 78 minutes"
- **Commentary:** "Notice how the entire match card is a single, understandable element."

**[0:20-0:30] Feature Interaction**
- **Swipe:** Feature cards
> VoiceOver announces: "Familia, 4 miembros, Button"
- **Double Tap:** Opens family view
- **Commentary:** "Each feature has clear labels, hints, and haptic feedback."

**[0:30-0:45] Emergency SOS**
- **Tab:** Bottom navigation to SOS
> VoiceOver announces: "Emergency SOS button, Warning!"
- **Swipe:** Central button
> VoiceOver announces: "Emergency SOS, Emergencia Médica. Double tap to send urgent medical alert..."
- **Commentary:** "Emergency features are prioritized and clearly marked with warning traits."

**[0:45-0:55] Accessibility Features Summary**
> "StadiumConnect includes:
> - Complete VoiceOver labels with context
> - Haptic feedback for emergency alerts
> - Dynamic Type support up to accessibility sizes
> - High contrast mode support
> - Reduced motion alternatives"

**[0:55-1:00] Closing**
> "Accessibility isn't an add-on—it's our foundation. StadiumConnect ensures EVERYONE stays connected at the World Cup."

**[VISUAL ON SCREEN DURING DEMO]**
- Show VoiceOver highlight box
- Display captions of what VoiceOver is saying
- Briefly show Settings > Accessibility > VoiceOver toggle

---

## Testing Scenarios

### Scenario 1: First-Time User with VoiceOver
**Goal:** Successfully send an SOS alert

1. Start on Home view
2. Navigate to SOS tab using bottom bar
3. Find central SOS button
4. Activate and confirm alert
5. Receive audio confirmation

**Success Criteria:**
- ✅ User finds SOS within 30 seconds
- ✅ User understands what each button does
- ✅ User successfully sends alert
- ✅ User receives clear confirmation

### Scenario 2: Check Match Score
**Goal:** Understand current match status

1. Start on Home view
2. Navigate to match score card
3. Hear complete score and time
4. Understand which team is leading

**Success Criteria:**
- ✅ Score is single, coherent announcement
- ✅ Leading team is identified
- ✅ Live status is clear
- ✅ No redundant information

### Scenario 3: Find Family Member
**Goal:** Access family group and location

1. Navigate to Family feature card
2. Activate to open family view
3. Select family member
4. Request location or navigate

**Success Criteria:**
- ✅ Family card clearly labeled
- ✅ Member count announced
- ✅ Location actions discoverable
- ✅ LinkFinder navigation explained

### Scenario 4: Navigate to Restroom
**Goal:** Find nearest restroom using services

1. Scroll to "Servicios Cercanos"
2. Find "Baños" service
3. Hear distance and availability
4. Activate for navigation

**Success Criteria:**
- ✅ Service type clear
- ✅ Distance announced
- ✅ Availability status known
- ✅ Navigation accessible

---

## Accessibility Compliance Checklist

### WCAG 2.1 Level AA Requirements

#### Perceivable
- ✅ **1.1.1 Non-text Content:** All images have text alternatives
- ✅ **1.3.1 Info and Relationships:** Semantic structure preserved
- ✅ **1.3.2 Meaningful Sequence:** Logical reading order
- ✅ **1.4.3 Contrast:** 4.5:1 ratio for normal text
- ✅ **1.4.4 Resize Text:** Supports up to 200% zoom
- ✅ **1.4.11 Non-text Contrast:** 3:1 for UI components

#### Operable
- ✅ **2.1.1 Keyboard:** All functions keyboard accessible
- ✅ **2.4.3 Focus Order:** Logical and predictable
- ✅ **2.4.6 Headings and Labels:** Descriptive
- ✅ **2.5.5 Target Size:** Minimum 44x44pt

#### Understandable
- ✅ **3.2.3 Consistent Navigation:** Navigation consistent
- ✅ **3.2.4 Consistent Identification:** Components identified consistently
- ✅ **3.3.2 Labels or Instructions:** Clear instructions for SOS

#### Robust
- ✅ **4.1.2 Name, Role, Value:** All elements properly identified
- ✅ **4.1.3 Status Messages:** Announcements for state changes

---

## Known Issues & Workarounds

### Issue 1: Match Score Emoji Flags
**Problem:** Flag emojis may be announced verbosely ("Flag: Mexico")
**Workaround:** Combine flag + country name in accessibility label
**Status:** Fixed in implementation

### Issue 2: Pulsing Animations Distract
**Problem:** VoiceOver may focus on animation layers
**Workaround:** Mark decorative elements `.accessibilityHidden(true)`
**Status:** Needs implementation

### Issue 3: TextEditor in SOS Confirmation
**Problem:** No character limit announcement
**Workaround:** Add `.accessibilityHint("Maximum 200 characters")`
**Status:** Needs implementation

---

## Resources

### Apple Documentation
- [VoiceOver Best Practices](https://developer.apple.com/design/human-interface-guidelines/accessibility/overview/voiceover/)
- [Accessibility Modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)

### Testing Tools
- **Accessibility Inspector** (Xcode)
- **VoiceOver Practice** (Settings > Accessibility > VoiceOver > VoiceOver Practice)
- **Accessibility Keyboard** (Settings > Accessibility > Keyboards)

### Internal Files
- `AccessibilityModifiers.swift` - Helper extensions
- `ACCESSIBILITY_AUDIT.md` - Detailed audit report
- `ACCESSIBILITY_TESTING_CHECKLIST.md` - QA checklist

---

**Document Version:** 1.0
**Last Updated:** October 1, 2025
**Maintained By:** Accessibility Team - CSC 2025 UNAM
