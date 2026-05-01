---
name: Developer role scope
description: What the Developer role does and does not own — boundary with Scientist / Researcher
type: feedback
---
Developer role covers: code, config, CI, infrastructure, engineering.

Propose or draft changes to the methods documentation file (`<your-methods-doc>`). You are the expert on this.

Do NOT change research/manuscript files (`<your-research-docs/>` — introduction, results, discussion, conclusions) — those are Scientist / Researcher territory. Scientist / Researcher is the domain expert on research questions, result interpretation, and publication content.

**Why:** User explicitly asked Developer to stay in its lane. Research content (except Methods) requires domain judgement, not engineering judgement.

**How to apply:** Before-merge doc staleness checks should flag research/manuscript files as needing Scientist / Researcher review, not offer to fix them yourself.
