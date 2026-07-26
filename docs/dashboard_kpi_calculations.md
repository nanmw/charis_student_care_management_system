# Dashboard finance KPI – calculation spec

This document specifies how each dashboard finance KPI is derived from fee and payment data. It covers the general finance block, Balance Due – This Month, aged arrears, trend, collection rate, and per-student monthly balance.

## Period definitions

- **Academic session:** Code format `YYYY` (e.g. `2026`). Session months run from **February through October** of that calendar year (**9 months**). Legacy codes `YYYY-YYYY` are treated as the start year only.
- **Current month:** The calendar month (year, month) used for “this month” KPIs. Default is `DateTime.now()`; can be overridden by a month selector.
- **Expected per student per month:** `monthlyTuitionFee` (from settings / `defaultMonthlyTuitionFee`). Session tuition = monthly × `sessionFinanceMonthCount` (9).

## Data sources

- **Payments:** One row per student per payment **year** (calendar year). Columns: `jan` … `dec`, `lumpSum`. For the current single-year session, typically one row per student (year = session code). Monthly amount for a given (year, month) is read from the row with that `year` and the corresponding month column. **Lump sum** counts toward session totals and balance brought forward.
- **Students:** Active students in scope (facilitator scope: class + mode when applicable).

## KPI formulas

### 1. Total Expected for the month of [Month] + balance brought forward

- **Balance brought forward (B/F):** For each student, `expectedPrior = numMonthsBefore × expectedPerMonth` (months from session start to end of **previous** month). `paidPrior` = sum of payments in those months **plus `lumpSum`** on the student’s session payment row(s). `bfStudent = max(0, expectedPrior − paidPrior)`. **Total B/F** = sum of `bfStudent` over all students.
- **Expected this month:** `expectedThisMonth = studentCount × expectedPerMonth`.
- **Total Expected + B/F:** `balanceBf + expectedThisMonth`.

### 2. Total Paid

- Sum over all students of the payment amount for the **selected month** (current or chosen calendar year + month), from the payment row for that year. If no row exists for that year, treat as 0. (Month-only total; lump sum is not allocated to a single month here.)

### 3. Total Balance Due (session-wide)

- For each student: `totalPaid` = sum of Feb–Oct monthly amounts + `lumpSum` over payment rows for that student in the session. `balance = sessionTuition − totalPaid`. **Total Balance Due** = sum of `max(0, balance)` over all students.

### 4. Balance Due – This Month (primary KPI)

- **Balance due this month** = `expectedThisMonth − paidThisMonth`, clamped to ≥ 0. Same “expected this month” and “Total Paid” as above. Represents the shortfall for the selected month only.

### 5. Delta vs previous month

- **Previous month balance due:** Same as “Balance Due – This Month” but for the previous calendar month (within the session). If that month is not in the session, no delta is shown.
- **Delta %:** `(balanceDueThisMonth − previousMonthBalanceDue) / previousMonthBalanceDue × 100` when `previousMonthBalanceDue > 0`. Positive = more due than last month (worse).

### 6. Collection rate (% of fees collected this month)

- **Collection rate %** = `(paidThisMonth / expectedThisMonth) × 100` when `expectedThisMonth > 0`, else 0. No cap; can exceed 100% if overpayments are applied to the month.

### 7. Aged arrears (0–30, 31–60, 61–90, 90+ days)

- Days overdue are **approximated by month**. Session months are ordered from start (February) to end (October). “Current” month index = selected month’s index in that list.
- For each month **up to and including** the current month: **shortfall** = sum over students of `max(0, expectedPerMonth − paidForThatMonth)`.
- **Bucket assignment:** Current month shortfall → **0–30 days**. One month before → **31–60 days**. Two months before → **61–90 days**. Three or more months before → **90+ days**.
- Each bucket value is the sum of shortfalls for the months in that “age” group.

### 8. Trend – Monthly Balance Due (last session months)

- For each month in the session up to the current month, **monthly balance due** = sum over students of `max(0, expectedPerMonth − paidForThatMonth)` for that month. Used for the trend bar chart.

### 9. Balance due as expected monthly (per student / cohort)

- **Per student:** `expectedPerMonth − paidThisMonth` for the current (or selected) month, clamped to ≥ 0. Shown in the “Balance due as expected monthly” column.
- **Per cohort:** Sum of the above over students in that cohort. Shown in the cohort summary table in the same column.

## Edge cases

- **Partial payments:** Any amount paid in a month reduces that month’s shortfall. No separate “payment plan” logic; everything is treated as monthly amounts in the payment columns.
- **Session not yet started / month not in session:** For a month outside the session, expected and paid for that month are 0; “Balance Due – This Month” and collection rate are 0 (or N/A). Aged arrears and trend only include months within the session.
- **Multiple payment rows per student:** All rows for the session are aggregated (sum of session totals). Amount for (year, month) is taken from the row with that calendar year.
- **Lump sum:** Counts fully toward session paid / B/F; does not reduce a single month’s “paid this month” KPI unless entered in a month column.
- **Overpayment in a month:** `paidThisMonth` can exceed `expectedThisMonth`; “Balance Due – This Month” is clamped to 0; collection rate can exceed 100%.

## Alert thresholds (risk highlighting)

- **Balance Due – This Month:** If `balanceDueThisMonth ≥ dashboardBalanceDueAlertThreshold` (Rand), the primary KPI card uses the error/risk color.
- **Aged arrears:** If `bucket90Plus / totalBalanceDue ≥ dashboardArrears90PercentAlertThreshold` (e.g. 0.25), the 90+ bar and/or section border use the error color. Thresholds are in `AppConstants`.
