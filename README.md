# Charis Student Care Management System

Flutter desktop application replacing Excel-based Student Care Data Capture System for Charis Bible College Cape Town.

## Features

- Offline-first architecture with multi-user sync via a Neon Postgres change-set log
- Git-inspired change-set synchronization (push and pull new rows; merge by timestamp)
- Role-based access control (Facilitator, Admin Level 02, Admin Level 01)
- Student management with alphabetical sorting
- Attendance tracking with percentage calculation
- Test score tracking with outstanding count
- Payment tracking with balance calculation
- Dashboard with aggregated summaries

## Tech Stack

- Flutter 3.x (Windows + macOS)
- Riverpod 2.x (State Management)
- Drift (Type-safe SQLite with encryption)
- Microsoft Entra ID (OAuth2 Authentication)
- Sync: incremental change-set push/pull to a Neon Postgres database (local SQLite stays the database each screen reads)

## Getting Started

### Prerequisites

1. Install Flutter SDK (3.0.0 or higher)
2. Set up Microsoft Entra ID (Azure AD) Application:
   - Go to [Azure Portal](https://portal.azure.com)
   - Navigate to **Azure Active Directory** → **App registrations**
   - Click **New registration**
   - Set redirect URI: `http://localhost:8080/callback`
   - Note your **Application (client) ID** and **Directory (tenant) ID**

### Running the App

1. Run `flutter pub get`
2. Run the app with authentication configuration:
   
   **Windows:**
   ```bash
   flutter run -d windows --dart-define=CHARIS_AUTH_CLIENT_ID=your-client-id-here --dart-define=CHARIS_AUTH_TENANT_ID=your-tenant-id-or-common
   ```
   
   **macOS:**
   ```bash
   flutter run -d macos --dart-define=CHARIS_AUTH_CLIENT_ID=your-client-id-here --dart-define=CHARIS_AUTH_TENANT_ID=your-tenant-id-or-common
   ```

   **Note:** Replace `your-client-id-here` with your Azure AD Application (client) ID. Use `common` for `CHARIS_AUTH_TENANT_ID` if you want multi-tenant support, or your specific tenant ID for single-tenant.

### Bypass auth for local development

To skip Microsoft sign-in and use a fake "Dev User" (Admin Level 01) so you can develop without Azure:

```bash
flutter run -d windows --dart-define=CHARIS_AUTH_SKIP=true
```

You will go straight to the app. Do **not** use this in production.

### Sync (change-set via Neon)

Each PC keeps its own SQLite database. Sync sends new change-sets to a shared Neon Postgres table and pulls change-sets from other PCs.

1. Create a free Neon project and open its SQL editor.
2. Run the script in [docs/neon_change_sets.sql](docs/neon_change_sets.sql) once.
3. Copy the **pooled** connection string (the host contains `-pooler`, and it uses `sslmode=require`).
4. In the app, go to **Settings → Sync**, paste that string, and save. It is stored only on that PC and is not shown again.
5. Repeat on each PC. Use **Sync now**, or leave auto-sync on. Auto-sync checks about once a minute while the app is open, and the app also syncs after you save.

The first sync uploads the change-sets already on that PC. Later syncs send only new edits. The free Neon compute sleeps after a few idle minutes and wakes on the next sync.

Do not commit the connection string.

### Alternative: Using Environment Variables

You can also set environment variables before running:

**Windows (PowerShell):**
```powershell
$env:CHARIS_AUTH_CLIENT_ID="your-client-id-here"
$env:CHARIS_AUTH_TENANT_ID="your-tenant-id-or-common"
flutter run -d windows
```

**macOS/Linux:**
```bash
export CHARIS_AUTH_CLIENT_ID="your-client-id-here"
export CHARIS_AUTH_TENANT_ID="your-tenant-id-or-common"
flutter run -d macos
```

## Development

See `.cursor/rules.md` for development guidelines and business rules.

## Academic sessions

- **What is an academic session?**  
  An academic session is one calendar year **Jan–Oct** (for example code `2026` = Jan 2026–Oct 2026). It is stored in the `academic_sessions` table and referenced by core tables (students, tests, attendance, payments, ministry entries, missions, mission payments) via `academic_session_id`. Each session has **3 terms** (e.g. Term 1 Jan–Apr, Term 2 May–Jul, Term 3 Aug–Oct).

- **Current academic session**  
  The currently selected session is stored in the `app_settings` table under the key `current_academic_session`. Only **Admin (Level 01)** can set or change it, from the **Settings** screen (Academic session section). The UI reads this value via `AcademicSessionRepository` and Riverpod providers. Reports and dashboards use the current session to scope queries (e.g. test results, balances, ministry hours).

- **Managing academic sessions**  
  On **Settings** (admin only), the admin can create and edit sessions (code, start date, end date, display name, current/active). Suggestions are provided (e.g. current year as code, 1 Jan–31 Oct as dates). The Tests and Payments screens only **filter** by session; they do not set the global current session.

- **Legacy data and backward compatibility**  
  Existing data that used plain `year` or string `academic_session` values is automatically migrated to `academic_session_id` where possible. Legacy session codes (e.g. `2024-2025`) are still supported; single-year codes (e.g. `2026`) are the standard. Older columns (`year`, `tests.academic_session`, etc.) are kept for now and are still written in parallel so older exports and tooling continue to work.

  **Transitional query behaviour:** Session-scoped repository methods prefer rows where `academic_session_id` matches the resolved session. They also **include legacy rows** where `academic_session_id` is null but the `year` (or session string) maps to the same session. So dashboards and reports show both new session-tagged data and old year-only data for the chosen session.
