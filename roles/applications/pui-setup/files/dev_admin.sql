-- Development seed requested for initial PUI production access.
INSERT INTO users (full_name, email, password_hash, role)
VALUES (
    'Alfian Gading',
    'gading@gmail.com',
    crypt('password', gen_salt('bf')),
    'user'
)
ON CONFLICT (email) DO UPDATE
SET full_name = EXCLUDED.full_name,
    role = EXCLUDED.role;

INSERT INTO users (full_name, email, password_hash, role)
VALUES (
    'Admin HashBox',
    'admin@gmail.com',
    crypt('password', gen_salt('bf')),
    'admin'
)
ON CONFLICT (email) DO UPDATE
SET full_name = EXCLUDED.full_name,
    role = EXCLUDED.role;
