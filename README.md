# Charis Student Care Management System

Flutter desktop application replacing Excel-based Student Care Data Capture System for Charis Bible College Cape Town.

## Features

- Offline-first architecture with multi-user sync via a shared OneDrive folder (change-set sync; no API; OneDrive desktop required)
- Git-inspired change-set synchronization (export/import JSON; merge by timestamp)
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
- Sync: change-set export/import to a shared OneDrive folder (no API; OneDrive desktop syncs files)

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

### Sync (change-set via OneDrive folder)

Sync uses a shared folder (no API). In the app, go to **Settings** → **Sync**, choose a folder inside your OneDrive (e.g. `OneDrive\\CharisStudentCare\\Sync`). All devices that use the same folder will exchange change-sets. OneDrive desktop must be installed so the folder syncs. Sync runs on startup and you can use **Sync now** in Settings.

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
  An academic session represents one academic year (for example `2024-2025`). It is stored in the `academic_sessions` table and referenced by core tables (students, tests, attendance, payments, ministry entries, missions, mission payments) via `academic_session_id`.

- **Current academic session**  
  The currently selected session is stored in the `app_settings` table under the key `current_academic_session`. The UI reads this value via `AcademicSessionRepository` and Riverpod providers. Reports and dashboards use the current session to scope queries (e.g. test results, balances, ministry hours).

- **Creating a new academic session each year**  
  When a new academic year starts, an admin should:
  1. Create a new academic session with the desired code (e.g. `2025-2026`).
  2. Mark the new session as active (the app ensures only one active session at a time).
  3. The `current_academic_session` setting is updated to this new code so all new records (tests, payments, attendance, ministry, missions) are associated with the correct session.

- **Legacy data and backward compatibility**  
  Existing data that used plain `year` or string `academic_session` values is automatically migrated to `academic_session_id` where possible (e.g. `2024` → `2024-2025`). Older columns (`year`, `tests.academic_session`, etc.) are kept for now and are still written in parallel so older exports and tooling continue to work.

  **Transitional query behaviour:** Session-scoped repository methods (e.g. `watchPaymentsForSession`, `watchForSession` for mission payments) prefer rows where `academic_session_id` matches the resolved session. They also **include legacy rows** where `academic_session_id` is null but the `year` (or session string) maps to the same session code. So dashboards and reports show both new session-tagged data and old year-only data for the chosen session. After everything uses `academic_session_id` in production, a follow-up migration could drop or ignore the legacy columns.
