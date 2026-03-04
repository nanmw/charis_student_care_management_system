# Manual QA: Academic Session FK Rollout

Use this checklist to verify that switching academic sessions correctly changes dashboards, reports, and new data tagging.

## Prerequisites

- Use a copy of realistic data (or create test data).
- Ensure at least two academic sessions exist (e.g. `2024-2025` and `2025-2026`). Create them in the app or via DB if needed.
- Set the **current academic session** in Settings (or wherever the app allows) so you can switch between sessions.

## 1. Dashboard

- [ ] Set current session to **2024-2025**. Note the dashboard values (e.g. total balance due, cohort summary totals, student summary totals).
- [ ] Set current session to **2025-2026**. Confirm that dashboard values change when the underlying data differs between sessions (e.g. different payments or mission schedules per session).
- [ ] Confirm that **Total balance due** and **Cohort summary** / **Student summary** use the current session (not a fixed calendar year).

## 2. Payments screen

- [ ] Open **Payments** and select academic session **2024-2025** from the Session dropdown. Confirm the table shows payment rows for that session.
- [ ] Switch the Session dropdown to **2025-2026**. Confirm the table updates (different rows or empty if no data for that session).
- [ ] Edit a payment for the selected session and **Save**. Confirm save succeeds and the row stays associated with that session (re-open or switch session and back to verify).

## 3. Missions payment screen

- [ ] Open **Missions payment** and select session **2024-2025**. Confirm the schedule shows mission payment rows for that session.
- [ ] Switch the Session dropdown to **2025-2026**. Confirm the table updates.
- [ ] Add or edit a mission payment for the selected session and **Save**. Confirm the row is stored for that session.

## 4. Export & reports

- [ ] Open **Export / Reports** and choose a **Payments** or **Tests** report.
- [ ] Select an **Academic session** (e.g. 2024-2025). Export the report. Confirm the exported data matches the selected session (e.g. only payments/tests for that session).
- [ ] Change the academic session and export again. Confirm the second export differs where the data differs by session.

## 5. New data tagging

- [ ] Set current academic session to **2025-2026**.
- [ ] Add a **new student**. Confirm the student is tagged with the current session (e.g. `academic_session_id` set for 2025-2026 in DB or visible in session-scoped lists).
- [ ] Add or edit a **test** with an academic session. Confirm the test row has `academic_session_id` set when the session is resolved.
- [ ] Create a **payment** or **mission payment** for the current session. Confirm the new row has `academic_session_id` set.

## 6. Backward compatibility

- [ ] With at least one session that has **legacy** rows (no `academic_session_id`, only `year` or session string), open the dashboard and reports for that session. Confirm legacy rows still appear (e.g. payments for year 2024 still show when session 2024-2025 is selected).

---

After completing the checklist, document any failures or edge cases for follow-up.
