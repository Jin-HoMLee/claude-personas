---
name: morning-routine
description: Use when the user greets a PM session with "good morning" and wants the board recap, standup scan, and triage warm-up ritual.
---

# Morning Routine

This is a pedagogical example skill.
Copy it into an instance only when you want a morning greeting to trigger a structured PM warm-up.
The production-grade framework skill reference is `framework/skills/load-persona-memory`.

## Workflow

When the user says "good morning" in a PM session, run the warm-up in phases.
Do not batch the whole ritual into one response unless the user explicitly asks for the complete report.

### Step 1: Board Recap

Pull the live board state first.
Compare it with the last remembered session state if that memory exists.
Give a short, motivating recap of closures, merges, new work, and meaningful progress since the last session.
Keep board events separate from standup messages.

### Step 2: Standup

Read the team standup file if the project has one.
Create a dedicated `## Standup` section.
Surface messages addressed to PM and noteworthy pending cross-role activity.
Do not mix standup items into the board recap.

### Step 3: Pause

After the recap and standup section, pause for the user to react.
End with a short readiness question such as `Ready for triage?`

### Step 4: Triage Plan

After the user gives the go-ahead, identify newly created or under-specified issues.
Propose milestone, size, priority, and status changes as a diff table.
Verify issue bodies and parent/sub-issue links before claiming scope or linkage.

## Output Shape

Use a compact greeting plus an at-a-glance summary line.
Use visually distinct sections for board recap, standup, and triage.
Prefer bullets or a small table over long paragraphs.
Close each phase with one concrete next-action question.

## Relationship to Memory

The matching memory rule explains why this ritual exists and what preferences shaped it.
This skill carries the operational steps so the workflow is easier to invoke, inspect, copy, and adapt.
