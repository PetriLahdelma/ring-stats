# Usability Study Protocol

A plan for 5 to 8 moderated sessions that test whether Ring Stats keeps its
product promise: a private, honest, native, five-second signal strip. Results
decide which single improvement ships next. No sessions have been run yet;
record them in the findings log at the end.

## Participants

- 5 to 8 people who own an Oura ring and use a Mac daily.
- At least two who have never used a developer portal or an API key.
- At least one who uses VoiceOver or keyboard-only navigation, if available.
- Exclude project contributors.

Each participant uses their own Oura account and creates their own developer
application, so no health data or credentials pass through the facilitator.
Do not record the screen during credential entry. Do not keep notes of any
health values participants see.

## Setup

- Current signed release installed, never previously connected on the test Mac.
- A fresh macOS user account per session, or disconnect and delete local data
  between sessions.
- Think-aloud protocol; the facilitator does not help unless a task is blocked
  for three minutes.

## Tasks

| # | Task | Observe | Success |
| --- | --- | --- | --- |
| 1 | "Get your Oura stats into the menu bar." | Where they hesitate in the three Connection steps; whether they understand why a developer application is needed | Connected without facilitator help |
| 2 | "Glance at the menu bar and tell me how you slept." | Time from click to answer | Correct answer within five seconds |
| 3 | Show a stale state (disconnect Wi-Fi, then press Refresh Now). "Is what you see up to date?" | Whether "Not updated" and the status label are noticed and understood | Participant says which values are old |
| 4 | Show a missing permission (reauthorize without Stress). "What would you do next?" | Whether "Needs access" and the button lead to the fix | Participant finds Enable Stress Access |
| 5 | "Show only Readiness and Sleep, with Sleep first." | Discovery of Customize in the footer and of drag reordering | Done without help |
| 6 | "Remove Ring Stats' access to your Oura data." | Path to Disconnect and whether the deletion copy is trusted | Disconnect & Delete found and confirmed |
| 7 | Keyboard or VoiceOver only (when a participant uses them): repeat tasks 2 and 5 | Reading order, focus visibility, announcements | Completed with assistive technology |

## Measures

- Task success (yes, with help, no) and time on task.
- Five-second comprehension for task 2.
- Single Ease Question (1 to 7) after tasks 1, 3, and 5.
- One closing question: "What would make you trust this app more?"

## Analysis

1. Tabulate success and time per task.
2. Group observed problems by task and count how many participants hit each.
3. Rank problems by frequency times severity (blocked, slowed, cosmetic).
4. Pick one improvement that addresses the top problem. Candidates already
   noted: update discovery, metric-specific context, and a keyboard path
   through the metric strip.

## Findings log

| Session | Date | Participant profile | Tasks completed | Notable problems |
| --- | --- | --- | --- | --- |
| Not yet run | | | | |
