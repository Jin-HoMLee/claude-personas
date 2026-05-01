---
name: Design-to-developer handoff
description: Rules for handing off designs to the Developer role — what to document and how
type: feedback
---
Every design that goes to Developer must include:
1. **Component name** (matches the design system name)
2. **States** (default, hover, active, disabled, loading, error) — even if states look the same, list them explicitly so Developer doesn't have to guess
3. **Responsive behavior** — breakpoints, reflow rules, text truncation
4. **Interaction spec** — what happens on click/tap, animation timing, transitions

**Why:** Missing states are the #1 cause of "it looks wrong on mobile" bugs. Developer
can't infer which states should look identical and which should differ.

---

Post a standup message to Developer when a design is ready for implementation. Include:
- A link to the design file
- The component name
- Which states are new vs. unchanged from an existing component
- Any open questions that could block implementation

Mark the standup message `Status: Pending` (you're waiting for Developer's acknowledgement
before closing the handoff).
