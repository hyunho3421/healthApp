# Remaining pages Vercel/Toss redesign

## Goal
Apply the approved clean Vercel/Toss-inspired visual language beyond Home, focusing on Add Workout, Stats, Profile, and especially select/dropdown interactions.

## Scope
- Replace default `DropdownButtonFormField` controls with card/bottom-sheet pickers.
- Refresh Add Workout page structure: hero summary, grouped cards, modern set rows.
- Refresh custom exercise registration dialog to match the same visual language.
- Refresh Stats and Profile surfaces with softer cards, clearer hierarchy, and consistent controls.
- Keep existing data flow and labels stable where possible.
- Build release/debug APKs and copy only stable filenames to `G:\내 드라이브\dev`.

## Completion
- `flutter analyze` passes.
- Release and debug APKs build.
- Drive contains:
  - `muscle_growth_diary-release.apk`
  - `muscle_growth_diary-debug.apk`
- No dated APK names are produced.
