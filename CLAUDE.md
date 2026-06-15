# Clothing app — iOS Frontend

This is the **SwiftUI/MVVM iOS frontend** of the clothing app ("Clothedd"). It talks to a backend and is part of a 3-project system.

**Before re-scanning this folder, load context from the `clothing-sprint` skill:**
- `~/.claude/skills/clothing-sprint/reference/frontend.md` — this app's full map (stack, files, build commands, gotchas)
- `~/.claude/skills/clothing-sprint/reference/architecture.md` — how it connects to the backend + content engine
- `~/.claude/skills/clothing-sprint/playbook.md` — **read before building** (proven commands / known failures)

Quick facts:
- Build (sim): `xcodebuild -scheme 20260312v2clothingfrontend -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -quiet`
- Backend URL is hardcoded at `Services/NetworkManager.swift:56`.
- No Railway deploy for this app (built via Xcode).

**After fixing any failure, silently update the skill playbook** (`~/.claude/skills/clothing-sprint/playbook.md`) so the next session skips the dead end.
