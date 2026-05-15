# Zotero note format (HTML, 3 sections)

**Rule:** Notes attached to Zotero items follow a fixed structure: **Findings / Methods / vs. our pipeline**. Bold-keyword leads. Telegraphic bullets, ~8 words each, ~18-word cap. 2–3 bullets per section. Push HTML directly to Zotero (no markdown preview).

**Why:** Consistent shape makes notes scannable across hundreds of items. Bold leads serve as ad-hoc tags.

**How to apply:** Use `python research/scripts/zotero_add.py <DOI> --note "..."` with the HTML body. The 3 sections are non-negotiable; "vs. our pipeline" forces explicit relevance framing.

Carry over from splice (Scientist role, 2026-05-08).
