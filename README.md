# SkidTrack Cloud
Production-oriented static web app using Supabase for employee authentication and a shared PostgreSQL database. Deploy to Vercel, Netlify, Cloudflare Pages, or any HTTPS static host.

## Setup
1. Create a Supabase project.
2. Run `supabase/schema.sql` in the SQL Editor.
3. Enable Email/Password authentication in Supabase Auth.
4. In `index.html`, replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY`.
5. Deploy the folder to a static HTTPS host. Vercel is supported via `vercel.json`.
6. Create employee accounts in Supabase Auth. Add corresponding rows to `profiles`.

## Security
The browser only contains the Supabase anonymous key. Never put the Supabase service-role key in this app.
