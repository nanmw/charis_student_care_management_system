# Charis Student Care Management System - Cursor Rules

## Project Overview

Flutter desktop application (Windows + macOS) replacing Excel-based Student Care Data Capture System for Charis Bible College Cape Town. Offline-first architecture with multi-user sync via OneDrive using Git-inspired change-sets.

## Critical Business Rules (MUST FOLLOW)

### Alphabetical Sorting

- **ALWAYS** maintain alphabetical ordering by surname in ALL student lists
- Auto-sort on: load, save, add, edit operations
- Use `ORDER BY surname ASC` in all database queries
- Re-sort immediately after any student operation
- Centralize sorting logic in `SortStudentsAlphabetically` use case

### No Direct Deletions

- **NEVER** implement delete operations for students
- Only allow status changes: Active → Withdrawn / Transferred
- Remove delete buttons from UI entirely
- Use soft delete via status field only
- Log status changes as `STATUS_CHANGE` change-sets, never `DELETE`

### Status Management

- Withdraw/Transfer must use guided modal that:
  - Updates status field
  - Logs change-set with operation type `STATUS_CHANGE`
  - Records timestamp and user_id
- Default view shows Active students only
- Optional filters for Withdrawn/Transferred

### Summary Sheet Aggregation

- **NEVER** store aggregated values redundantly
- Calculate all summaries on-demand from source data:
  - Attendance % ← calculated from Attendance table
  - Outstanding tests ← count where score < 70 from Tests table
  - Ministry hours ← sum per term vs required (15/7/5 for FT 1st/2nd/3rd, 6/4/2 for Hybrid)
  - Finance balance ← 19800 Rand full tuition - SUM(payments)
  - Mission fund ← only for 2nd year students
- Cache in memory (Riverpod) for performance, invalidate on data changes

### Role-Based Access Control

Enforce at THREE levels:

1. **UI Level**: `RoleGuard` widget hides/shows buttons/fields
2. **Repository Level**: Check role before write operations
3. **Service Level**: Validate role in API calls (if any)

**Roles:**

- **Facilitator**: Data entry only (attendance, hours, tests) - NO financials, NO student add/edit
- **Admin Level 02** (Intern over student care): Full access EXCEPT financials - can add/edit students, attendance, tests, hours
- **Admin Level 01** (Director/Dean/Admin): Full access including financials

## Branding Requirements (STRICT)

### Typography

- **Font Family**: Questrial
  - Headings: Questrial (use weight 600–700 where needed)
  - Body text: Questrial (400)
- Loaded from local font file: `assets/fonts/Questrial/Questrial-Regular.ttf`
- Declared in `pubspec.yaml` under `fonts` section
- Fallback to system fonts if font file unavailable

### Color Palette

```dart
// Charis Reds (Primary)
const charisRedDark = Color(0xFF58001d);      // #58001d
const charisRedPrimary = Color(0xFF7d0023);   // #7d0023 (primary buttons/accent)
const charisRedLight = Color(0xFF8b0029);    // #8b0029 (lighter highlights)

// Neutrals
const charisBlack = Color(0xFF151515);        // #151515
const charisDarkGray = Color(0xFF2c2c2c);     // #2c2c2c
const charisMidGray = Color(0xFF696969);     // #696969
const charisLightGray = Color(0xFFe6e6e6);    // #e6e6e6
const charisWhite = Color(0xFFffffff);        // #ffffff
```

### UI Style

- Material 3 design system
- Clean, professional appearance
- Maroon/red accents on white/light backgrounds
- Subtle elevation (shadows)
- Consistent spacing and padding

## Architecture Standards

### Tech Stack

- **Framework**: Flutter 3.x (desktop: Windows + macOS)
- **State Management**: Riverpod 2.x
- **Database**: Drift (type-safe SQLite) + sqlcipher_flutter_libs (encryption)
- **Sync**: Git-inspired change-sets (JSON patches/deltas)
- **Auth**: Microsoft Entra ID (OAuth2)
- **UI Tables**: syncfusion_flutter_datagrid
- **PDF Export**: flutter_pdf

### Folder Structure

```
lib/
├── core/           # Constants, theme, utils, exceptions
├── data/           # Database, models, repositories, services
├── presentation/   # Providers, screens, widgets, routing
└── domain/         # Entities, use cases (business logic)
```

### Code Organization

- **Repositories**: Business logic + data access, enforce rules
- **Providers (Riverpod)**: State management, role checks
- **Use Cases**: Pure business logic (calculations, validations)
- **Services**: External integrations (Auth, OneDrive, PDF)

## Sync System Design

### Change-Set Structure

Every write operation creates a change-set:

```dart
{
  id: UUID,
  table: String,           // 'students', 'attendance', 'payments', etc.
  record_id: String,       // ID of affected record
  operation: String,        // 'INSERT', 'UPDATE', 'STATUS_CHANGE'
  payload: Map<String, dynamic>,  // JSON representation of changes
  timestamp: DateTime,
  user_id: String,
  version: int             // Increment on each write (optimistic locking)
}
```

### Sync Flow

1. **Pull**: Fetch remote change-sets from OneDrive
2. **Compare**: Check versions/timestamps
3. **Merge**:
   - Non-critical fields (attendance, tests): Last-write-wins
   - Critical fields (payments, status): Flag conflict
4. **Resolve**: Show conflict resolution modal (side-by-side UI)
5. **Push**: Send local change-sets to OneDrive

### Conflict Resolution

- **Non-critical**: Automatic merge (last-write-wins)
- **Critical** (payments, status): Manual resolution required
- Show side-by-side comparison in modal
- Admin Level 01 only can resolve conflicts

## Financial Rules

### Tuition

- **Full Tuition**: 19800 Rand (hardcoded constant)
- **Balance Calculation**: `19800 - SUM(all_payments)`
- Display in Rand currency format: `R 19,800.00`
- Handle partial payments correctly

### Payments

- Support monthly payments and lump-sum payments
- Track payment date, amount, payment type
- Calculate running balance
- Only Admin Level 01 can enter/view payments

## Data Capture Rules

### Attendance

- Daily entry with date picker
- Waiver checkboxes for excused absences
- Calculate percentage: `(total_present / total_days) * 100`
- Focus on Full-Time 1st year (MVP), expandable later

### Tests

- Score entry (0-100)
- Auto-determine pass/fail: `score >= 70` = pass
- Outstanding count: count where `score < 70`
- Display outstanding indicator prominently

### Ministry Hours (Post-MVP)

- Requirements per term:
  - Full-Time: 1st year (15), 2nd year (7), 3rd year (5)
  - Hybrid: 1st year (6), 2nd year (4), 3rd year (2)
- MVP: Placeholder in dashboard
- Post-MVP: Full tracking and calculation

### Mission Fund (Post-MVP)

- Only for 2nd year students
- MVP: Placeholder
- Post-MVP: Track and display

## MVP Scope (Must-Have for First Release)

### Core Features

- ✅ Microsoft login + role enforcement
- ✅ Student list (alphabetical) + add student (modal, surname-first)
- ✅ Attendance entry (Full-Time 1st year focus, daily, with waiver checkboxes + % calc)
- ✅ Test entry (score → pass/fail/outstanding count)
- ✅ Payment entry (monthly/lump-sum, balance vs 19800 Rand)
- ✅ Simple dashboard: aggregated per-student summary (attendance %, outstanding tests, balance)
- ✅ Manual "Sync Now" button with conflict resolution modal (admin-only for critical fields)
- ✅ Basic PDF export of dashboard

### Post-MVP (Nice-to-Have, Do NOT Prioritize)

- Full multi-year/mode support
- Ministry hours + missions funding
- Withdrawn/transferred filtered views
- Audit log viewer
- Auto-sync + notifications

## Coding Standards

### Dart/Flutter

- Use `dart format` for code formatting
- Follow Flutter style guide
- Use meaningful variable/function names
- Add comments for complex business logic
- Use const constructors where possible

### Error Handling

- Use try-catch blocks for async operations
- Show user-friendly error messages
- Log errors for debugging
- Handle offline scenarios gracefully

### Testing

- Write unit tests for repositories and use cases
- Write widget tests for critical screens
- Write integration tests for full flows
- Test role-based access thoroughly

## Database Schema Guidelines

### Tables

- Use Drift table definitions
- Include `id` (primary key), `created_at`, `updated_at` fields
- Use foreign keys for relationships
- Index frequently queried fields (surname for sorting)

### Encryption

- Use sqlcipher_flutter_libs for encrypted SQLite
- Derive encryption key securely (from user credentials or app secret)
- Test encryption/decryption on app restart

## UI/UX Guidelines

### Forms

- Use `CharisTextField` widget for consistent styling
- Validate inputs before submission
- Show clear error messages
- Disable submit button while processing

### Modals

- Use Material 3 dialog components
- Include cancel/confirm buttons
- For status changes: guided flow with clear steps
- Show loading states during async operations

### Tables/Lists

- Use Syncfusion DataGrid for large datasets
- Always show alphabetical order indicator
- Include search/filter functionality
- Show loading skeletons while fetching

### Sync Status

- Show sync status indicator:
  - 🟢 Green = synced
  - 🟡 Yellow = pending changes
  - 🔴 Red = conflict detected
- Display last sync timestamp
- "Sync Now" button (manual trigger in MVP)

## Important Gotchas

1. **Alphabetical Sorting**: Enforce everywhere, never skip
2. **No Deletions**: Remove delete functionality entirely
3. **Aggregation**: Calculate on-demand, never store redundantly
4. **Role Checks**: Enforce at UI, repository, and service levels
5. **Offline-First**: All operations work offline, queue change-sets
6. **Change-Sets**: Log every write operation
7. **Conflicts**: Manual resolution for critical fields only
8. **Font Loading**: Ensure Questrial loads, fallback gracefully
9. **Currency**: Always format as Rand (R X,XXX.XX)
10. **Status Changes**: Use guided modal, log as STATUS_CHANGE

## When Implementing Features

1. **Check role permissions** before allowing any action
2. **Enforce alphabetical sorting** on all student lists
3. **Log change-sets** for every write operation
4. **Calculate aggregations** from source data, don't store
5. **Use Charis branding** (colors, fonts) consistently
6. **Handle offline** scenarios gracefully
7. **Show loading states** for async operations
8. **Validate inputs** before submission
9. **Test role-based access** thoroughly
10. **Follow Material 3** design guidelines

## Questions to Ask Before Implementing

- Does this maintain alphabetical sorting?
- Are role permissions checked?
- Is a change-set logged for this write?
- Does this calculate from source data (not redundant storage)?
- Does this follow Charis branding?
- Does this work offline?
- Is this in MVP scope or post-MVP?

---

**Remember**: This app replaces a critical Excel-based system. Accuracy, data integrity, and adherence to business rules are paramount. When in doubt, refer to the original user guide requirements.
