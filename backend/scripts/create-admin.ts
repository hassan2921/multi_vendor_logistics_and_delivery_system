import { supabaseAdmin } from '../src/config/supabaseClient';

async function main() {
  const email = process.argv[2];
  const password = process.argv[3];
  const fullName = process.argv[4] ?? 'Admin';

  if (!email || !password) {
    console.error('Usage: tsx scripts/create-admin.ts <email> <password> [fullName]');
    process.exit(1);
  }

  const { data: created, error: authError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (authError || !created.user) {
    console.error('Failed to create auth user:', authError?.message);
    process.exit(1);
  }

  const { error: rowError } = await supabaseAdmin
    .from('users')
    .insert({ auth_user_id: created.user.id, email, full_name: fullName, role: 'admin' });

  if (rowError) {
    console.error('Failed to create users row:', rowError.message);
    process.exit(1);
  }

  console.log(`Admin account created: ${email}`);
}

main();
