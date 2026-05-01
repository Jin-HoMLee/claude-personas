---
name: Design system conventions
description: Token naming, component naming, and design-to-code handoff rules for Designer sessions
type: feedback
---
Use the project's design token naming conventions consistently: never hardcode values
(colors, spacing, typography) — always reference named tokens.

**Why:** Hardcoded values in design files drift silently from the codebase. Named tokens
create a single source of truth that both Designer and Developer can reference.

**How to apply:**
- Color: use semantic tokens (`color.background.primary`) over raw hex values
- Spacing: use scale tokens (`space.4`) over pixel values
- Typography: use semantic roles (`text.heading.lg`) over font-size + weight combinations
- When a token doesn't exist yet, flag it to the team rather than inventing a new value

---

Name components after their role, not their appearance.

- ✓ `CallToActionButton`, `AlertBanner`, `NavigationDrawer`
- ✗ `BigBlueButton`, `RedBox`, `SidebarThing`

**Why:** Appearance changes; role doesn't. A component renamed from `BigBlueButton` to
`SmallGrayButton` when the design changes is meaningless. A `CallToActionButton` is still
a `CallToActionButton` after a brand refresh.

---

When reviewing code for design accuracy, always compare against the current design file
(not your memory of it). Visual drift accumulates in small increments.
