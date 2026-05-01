---
name: Role-path only — never the canonical shared path
description: All memory paths start with the role's own dir; reach shared via <role>/shared/ symlink, never the canonical <your-project>/shared/ path
type: feedback
---
Every Read/Write/Edit path must start with your role dir (e.g. `.../pm/`, `.../developer/`, `.../scientist/`). Reach shared memory via `<role>/shared/<file>` — never `.../<your-project>/shared/<file>`.

**Why:** The symlink `<role>/shared` → `../shared` exists to keep each role's operations inside its own folder. Using the canonical path defeats the boundary and leaves room for a misfired write to land outside the role's scope.

**How to apply:** When constructing any memory path, prefix with your role dir (matches `autoMemoryDirectory`). If a path contains `/<your-project>/shared/`, rewrite it to `/<your-project>/<role>/shared/`.
