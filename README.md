# Charis Student Care Management System

Flutter desktop application replacing Excel-based Student Care Data Capture System for Charis Bible College Cape Town.

## Features

- Offline-first architecture with multi-user sync via OneDrive
- Git-inspired change-set synchronization
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
- OneDrive API (Sync)

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
