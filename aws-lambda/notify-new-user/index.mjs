import nodemailer from 'nodemailer';

const { DATABASE_URL, SMTP_USER, SMTP_APP_PASSWORD, NOTIFY_TO_EMAIL } = process.env;

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 465,
  secure: true,
  auth: { user: SMTP_USER, pass: SMTP_APP_PASSWORD },
});

export const handler = async (event) => {
  let body;
  try {
    body = JSON.parse(event.body ?? '{}');
  } catch {
    return { statusCode: 400, body: 'Invalid JSON' };
  }

  const { uid, idToken } = body;
  if (!uid || !idToken) {
    return { statusCode: 400, body: 'Missing uid or idToken' };
  }

  // The RTDB rule for profile is `auth.uid == $uid`, so this read only
  // succeeds if idToken really belongs to this uid — no separate JWT
  // verification or Firebase service account needed.
  const res = await fetch(
    `${DATABASE_URL}/users/${encodeURIComponent(uid)}/profile.json?auth=${encodeURIComponent(idToken)}`,
  );

  if (!res.ok) {
    return { statusCode: 200, body: 'ignored' };
  }

  const profile = await res.json();
  if (!profile || profile.admin_approved !== false) {
    return { statusCode: 200, body: 'ignored' };
  }

  try {
    await transporter.sendMail({
      from: SMTP_USER,
      to: NOTIFY_TO_EMAIL,
      subject: 'Nuevo usuario pendiente de aprobación',
      text: [
        'Se ha registrado un nuevo usuario en Notification Reader y está pendiente de aprobación.',
        '',
        `Email: ${profile.email}`,
        `UID: ${uid}`,
        `Fecha: ${new Date().toISOString()}`,
      ].join('\n'),
    });
  } catch (err) {
    console.error('Failed to send notification email', err);
  }

  return { statusCode: 200, body: 'ok' };
};
