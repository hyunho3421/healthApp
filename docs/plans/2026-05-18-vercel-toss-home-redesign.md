# Vercel Toss Home Redesign Implementation Plan

> **For implementer:** Use TDD throughout where practical. For visual-only Flutter styling, protect existing widget behavior with analyzer and widget tests before/after.

**Goal:** Make the muscle growth diary feel less empty by applying a Vercel/Toss-inspired visual system to the app theme, home hero, weekly summary, empty state, and workout cards.

**Architecture:** Keep existing data/state/navigation intact. Add presentation-only private widgets inside `home_screen.dart` and update `ThemeData` in `main.dart` so all screens inherit cleaner cards, buttons, inputs, and app bars.

**Tech Stack:** Flutter Material 3, Riverpod, existing widget tests.

---

### Task 1: Add app-wide Vercel/Toss theme

**Files:**
- Modify: `lib/main.dart`

**Steps:**
1. Run `flutter test` to capture current state.
2. Replace the seed purple theme with a light Material 3 theme using blue primary, soft neutral background, rounded cards/buttons/inputs, and subtle dividers.
3. Run `dart format lib/main.dart`.
4. Run `flutter analyze` and `flutter test`.

### Task 2: Redesign home scaffold and hero

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart`

**Steps:**
1. Keep existing navigation callbacks and future loading logic unchanged.
2. Remove the default app bar from home and add a custom top section with title, subtitle, stat pills, and profile/stats icon buttons.
3. Put content on a soft background and preserve the existing FAB action.
4. Run `dart format lib/features/home/presentation/home_screen.dart`.
5. Run `flutter analyze` and `flutter test`.

### Task 3: Polish weekly and record cards

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart`

**Steps:**
1. Convert weekly summary into a white rounded card with horizontal day pills.
2. Upgrade daily summary and entry cards with rounded borders, metric tiles, soft chips, and stronger visual hierarchy.
3. Upgrade empty state with an icon badge and clearer CTA copy.
4. Run `dart format`, `flutter analyze`, and `flutter test`.

### Task 4: Final verification

**Files:**
- Inspect: `lib/main.dart`
- Inspect: `lib/features/home/presentation/home_screen.dart`

**Steps:**
1. Run full `flutter test`.
2. Run `flutter analyze`.
3. Report changed files and verification result.
