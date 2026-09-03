# SkidTrack - Add and Deploy Supabase Edge Function
# Function: admin-create-employee
# Project ref: secrzzjegeuppgziyojk
#
# Run this script from your SkidTrack repository folder in PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\add-skidtrack-edge-function.ps1
#
# Requirements:
# - Node.js / npm installed
# - Supabase account access to project secrzzjegeuppgziyojk

$ErrorActionPreference = "Stop"

$ProjectRef = "secrzzjegeuppgziyojk"
$FunctionName = "admin-create-employee"
$FunctionDir = Join-Path (Get-Location) "supabase\functions\$FunctionName"
$FunctionFile = Join-Path $FunctionDir "index.ts"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " SkidTrack Supabase Edge Function Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# 1. Verify Node/npm
# ------------------------------------------------------------

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: npm was not found." -ForegroundColor Red
    Write-Host "Install Node.js from https://nodejs.org and run this script again."
    exit 1
}

Write-Host "[1/6] npm found." -ForegroundColor Green

# ------------------------------------------------------------
# 2. Initialize Supabase project folder if necessary
# ------------------------------------------------------------

if (-not (Test-Path ".\supabase\config.toml")) {
    Write-Host "[2/6] Initializing Supabase configuration..." -ForegroundColor Yellow
    npx supabase init
}
else {
    Write-Host "[2/6] Supabase configuration already exists." -ForegroundColor Green
}

# ------------------------------------------------------------
# 3. Login and link project
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/6] Logging into Supabase..." -ForegroundColor Yellow
Write-Host "A browser window may open. Sign in with the Supabase account that owns SkidTrack."
npx supabase login

Write-Host ""
Write-Host "Linking project: $ProjectRef" -ForegroundColor Yellow
npx supabase link --project-ref $ProjectRef

# ------------------------------------------------------------
# 4. Create Edge Function source
# ------------------------------------------------------------

Write-Host ""
Write-Host "[4/6] Creating Edge Function source..." -ForegroundColor Yellow

New-Item -ItemType Directory -Force -Path $FunctionDir | Out-Null

$FunctionCode = @'
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(
  body: Record<string, unknown>,
  status = 200
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return jsonResponse(
      { error: "Method not allowed" },
      405
    );
  }

  try {
    const authHeader =
      req.headers.get("Authorization");

    if (!authHeader) {
      return jsonResponse(
        { error: "Missing authorization header" },
        401
      );
    }

    const supabaseUrl =
      Deno.env.get("SUPABASE_URL");

    const anonKey =
      Deno.env.get("SUPABASE_ANON_KEY");

    const serviceRoleKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (
      !supabaseUrl ||
      !anonKey ||
      !serviceRoleKey
    ) {
      return jsonResponse(
        {
          error:
            "Required Supabase environment variables are unavailable.",
        },
        500
      );
    }

    // --------------------------------------------------------
    // Authenticated client representing the logged-in caller
    // --------------------------------------------------------

    const userClient = createClient(
      supabaseUrl,
      anonKey,
      {
        global: {
          headers: {
            Authorization: authHeader,
          },
        },
      }
    );

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return jsonResponse(
        { error: "Not authenticated" },
        401
      );
    }

    // --------------------------------------------------------
    // Server-side admin client
    // Service role NEVER goes to the browser
    // --------------------------------------------------------

    const adminClient = createClient(
      supabaseUrl,
      serviceRoleKey,
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    );

    // --------------------------------------------------------
    // Verify caller is an active SkidTrack admin
    // --------------------------------------------------------

    const {
      data: callerProfile,
      error: callerError,
    } = await adminClient
      .from("profiles")
      .select("id, role, active")
      .eq("id", user.id)
      .maybeSingle();

    if (
      callerError ||
      !callerProfile ||
      callerProfile.role !== "admin" ||
      callerProfile.active !== true
    ) {
      return jsonResponse(
        { error: "Admin access required" },
        403
      );
    }

    // --------------------------------------------------------
    // Parse request
    // --------------------------------------------------------

    const body = await req.json();

    const fullName =
      String(body.full_name || "").trim();

    const username =
      String(body.username || "")
        .trim()
        .toLowerCase();

    const email =
      String(body.email || "")
        .trim()
        .toLowerCase();

    const password =
      String(body.password || "");

    const role =
      String(body.role || "")
        .trim()
        .toLowerCase();

    const allowedRoles = [
      "technician",
      "manager",
      "pipe_fitter",
      "electrician",
      "laborer",
      "welder",
      "superviser",
    ];

    // --------------------------------------------------------
    // Validation
    // --------------------------------------------------------

    if (!fullName) {
      return jsonResponse(
        { error: "Full name is required." },
        400
      );
    }

    if (
      !/^[a-z0-9._-]{3,40}$/.test(username)
    ) {
      return jsonResponse(
        {
          error:
            "Username must be 3-40 characters using letters, numbers, dots, underscores, or hyphens.",
        },
        400
      );
    }

    if (
      !email ||
      !email.includes("@")
    ) {
      return jsonResponse(
        { error: "A valid email is required." },
        400
      );
    }

    if (password.length < 6) {
      return jsonResponse(
        {
          error:
            "Temporary password must be at least 6 characters.",
        },
        400
      );
    }

    if (!allowedRoles.includes(role)) {
      return jsonResponse(
        { error: "Invalid employee role." },
        400
      );
    }

    // --------------------------------------------------------
    // Check duplicate username
    // --------------------------------------------------------

    const {
      data: existingUsername,
      error: usernameError,
    } = await adminClient
      .from("profiles")
      .select("id")
      .ilike("username", username)
      .maybeSingle();

    if (usernameError) {
      console.error(
        "Username lookup:",
        usernameError
      );

      return jsonResponse(
        {
          error:
            "Could not validate username: " +
            usernameError.message,
        },
        500
      );
    }

    if (existingUsername) {
      return jsonResponse(
        {
          error:
            "That username is already in use.",
        },
        409
      );
    }

    // --------------------------------------------------------
    // Create Supabase Auth user
    //
    // email_confirm:true allows the employee to immediately
    // sign in with the temporary password.
    // --------------------------------------------------------

    const {
      data: created,
      error: createError,
    } =
      await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: fullName,
          username,
        },
      });

    if (createError) {
      console.error(
        "Auth user creation:",
        createError
      );

      return jsonResponse(
        { error: createError.message },
        400
      );
    }

    if (!created.user) {
      return jsonResponse(
        {
          error:
            "Supabase did not return the newly created user.",
        },
        500
      );
    }

    const userId = created.user.id;

    // --------------------------------------------------------
    // Create/update employee profile.
    //
    // Your auth trigger may already have created this row.
    // Upsert guarantees the desired role and username.
    // --------------------------------------------------------

    const {
      error: profileError,
    } = await adminClient
      .from("profiles")
      .upsert(
        {
          id: userId,
          full_name: fullName,
          username,
          role,
          active: true,
        },
        {
          onConflict: "id",
        }
      );

    if (profileError) {
      console.error(
        "Profile creation:",
        profileError
      );

      // Roll back the Auth user if the profile failed.
      await adminClient.auth.admin.deleteUser(
        userId
      );

      return jsonResponse(
        {
          error:
            "Employee profile could not be created: " +
            profileError.message,
        },
        400
      );
    }

    return jsonResponse({
      success: true,
      user_id: userId,
      username,
      email,
      role,
    });
  } catch (error) {
    console.error(
      "admin-create-employee:",
      error
    );

    return jsonResponse(
      {
        error:
          error instanceof Error
            ? error.message
            : "Employee creation failed.",
      },
      500
    );
  }
});
'@

Set-Content `
    -Path $FunctionFile `
    -Value $FunctionCode `
    -Encoding UTF8

Write-Host "Created: $FunctionFile" -ForegroundColor Green

# ------------------------------------------------------------
# 5. Deploy Edge Function
# ------------------------------------------------------------

Write-Host ""
Write-Host "[5/6] Deploying Edge Function..." -ForegroundColor Yellow

npx supabase functions deploy $FunctionName --project-ref $ProjectRef --use-api

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Edge Function deployment failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

# ------------------------------------------------------------
# 6. Verify deployment
# ------------------------------------------------------------

Write-Host ""
Write-Host "[6/6] Verifying deployed functions..." -ForegroundColor Yellow

npx supabase functions list --project-ref $ProjectRef

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Edge Function deployment complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Function name:"
Write-Host "  $FunctionName" -ForegroundColor Cyan
Write-Host ""
Write-Host "Function URL:"
Write-Host "  https://$ProjectRef.supabase.co/functions/v1/$FunctionName" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your SkidTrack index.html can now call:"
Write-Host '  sb.functions.invoke("admin-create-employee", { body: {...} })' -ForegroundColor Cyan
Write-Host ""
