# ============================================================================
# Additional Vault Variables for New Applications
# ============================================================================
# These variables need to be added to group_vars/all/vault.yml
# Run: make vault-main (or ansible-vault edit --vault-password-file .vault_pass group_vars/all/vault.yml)
# Then copy and paste these sections at the end of the file
# ============================================================================

# ============================================================================
# MySQL Databases for New Applications
# ============================================================================
vault_mysql_posyandu_database: "posyandu"
vault_mysql_posyandu_username: "root"
vault_mysql_posyandu_password: "sJgJgT1PueVL23XL2~3cS4Sfz"

vault_mysql_solvo_database: "solvo"
vault_mysql_solvo_username: "root"
vault_mysql_solvo_password: "sJgJgT1PueVL23XL2~3cS4Sfz"

vault_mysql_presensi_skansaba_web_database: "presensi_skansaba"
vault_mysql_presensi_skansaba_web_username: "root"
vault_mysql_presensi_skansaba_web_password: "sJgJgT1PueVL23XL2~3cS4Sfz"

# ============================================================================
# PostgreSQL Databases for New Applications
# ============================================================================
vault_postgres_campus_project_hub_api_database: "campus_project_hub"
vault_postgres_campus_project_hub_api_username: "root"
vault_postgres_campus_project_hub_api_password: "sJgJgT1PueVL23XL2~3cS4Sfz"

vault_postgres_file_pod_api_database: "file_pod"
vault_postgres_file_pod_api_username: "root"
vault_postgres_file_pod_api_password: "sJgJgT1PueVL23XL2~3cS4Sfz"

vault_postgres_ruang_tenang_api_database: "ruang_tenang"
vault_postgres_ruang_tenang_api_username: "root"
vault_postgres_ruang_tenang_api_password: "sJgJgT1PueVL23XL2~3cS4Sfz"

# ============================================================================
# Application: Posyandu (Laravel + Inertia React)
# ============================================================================
vault_posyandu_app_name: "Posyandu"
vault_posyandu_app_key: "base64:GENERATE_NEW_KEY_WITH_php_artisan_key:generate"
vault_posyandu_app_url: "https://posyandu.alfian-gading.site"
vault_posyandu_db_host: "mysql-db"
vault_posyandu_db_port: "3306"
vault_posyandu_db_database: "{{ vault_mysql_posyandu_database }}"
vault_posyandu_db_username: "{{ vault_mysql_posyandu_username }}"
vault_posyandu_db_password: "{{ vault_mysql_posyandu_password }}"

# ============================================================================
# Application: Solvo (Laravel + Filament)
# ============================================================================
vault_solvo_app_name: "Solvo"
vault_solvo_app_key: "base64:GENERATE_NEW_KEY_WITH_php_artisan_key:generate"
vault_solvo_app_url: "https://solvo.alfian-gading.site"
vault_solvo_db_host: "mysql-db"
vault_solvo_db_port: "3306"
vault_solvo_db_database: "{{ vault_mysql_solvo_database }}"
vault_solvo_db_username: "{{ vault_mysql_solvo_username }}"
vault_solvo_db_password: "{{ vault_mysql_solvo_password }}"

# Midtrans Payment Gateway (Sandbox)
vault_solvo_midtrans_server_key: "SB-Mid-server-REPLACE_WITH_YOUR_KEY"
vault_solvo_midtrans_client_key: "SB-Mid-client-REPLACE_WITH_YOUR_KEY"

# ============================================================================
# Application: Presensi Skansaba Web (Laravel)
# ============================================================================
vault_presensi_skansaba_web_app_name: "Presensi Skansaba"
vault_presensi_skansaba_web_app_key: "base64:GENERATE_NEW_KEY_WITH_php_artisan_key:generate"
vault_presensi_skansaba_web_app_url: "https://presensi-skansaba.alfian-gading.site"
vault_presensi_skansaba_web_db_host: "mysql-db"
vault_presensi_skansaba_web_db_port: "3306"
vault_presensi_skansaba_web_db_database: "{{ vault_mysql_presensi_skansaba_web_database }}"
vault_presensi_skansaba_web_db_username: "{{ vault_mysql_presensi_skansaba_web_username }}"
vault_presensi_skansaba_web_db_password: "{{ vault_mysql_presensi_skansaba_web_password }}"

# ============================================================================
# Application: Campus Project Hub API (Go Gin)
# ============================================================================
vault_campus_project_hub_api_base_url: "https://campus-project-hub-api.alfian-gading.site"
vault_campus_project_hub_api_db_host: "postgres-db"
vault_campus_project_hub_api_db_port: "5432"
vault_campus_project_hub_api_db_name: "{{ vault_postgres_campus_project_hub_api_database }}"
vault_campus_project_hub_api_db_user: "{{ vault_postgres_campus_project_hub_api_username }}"
vault_campus_project_hub_api_db_password: "{{ vault_postgres_campus_project_hub_api_password }}"
vault_campus_project_hub_api_jwt_secret: "your-super-secret-jwt-key-change-in-production-at-least-32-chars"
# OAuth - Google
vault_campus_project_hub_api_google_redirect_url: "https://campus-project-hub-api.alfian-gading.site/api/v1/auth/google/callback"
# OAuth - GitHub
vault_campus_project_hub_api_github_client_id: "your-github-client-id"
vault_campus_project_hub_api_github_client_secret: "your-github-client-secret"
vault_campus_project_hub_api_github_redirect_url: "https://campus-project-hub-api.alfian-gading.site/api/v1/auth/github/callback"
# Midtrans
vault_campus_project_hub_api_midtrans_server_key: ""
vault_campus_project_hub_api_midtrans_client_key: ""
vault_campus_project_hub_api_midtrans_is_production: false
# Frontend URL
vault_campus_project_hub_api_frontend_url: "https://campus-project-hub-web.alfian-gading.site"

# ============================================================================
# Application: Campus Project Hub Web (Next.js)
# ============================================================================
vault_campus_project_hub_web_api_url: "https://campus-project-hub-api.alfian-gading.site/api"

# ============================================================================
# Application: File Pod API (Node.js Express + Prisma)
# ============================================================================
vault_file_pod_api_app_url: "https://file-pod-api.alfian-gading.site"
vault_file_pod_api_cors_origin: "https://file-pod-api.alfian-gading.site"
vault_file_pod_api_database_url: "postgresql://{{ vault_postgres_file_pod_api_username }}:{{ vault_postgres_file_pod_api_password }}@postgres-db:5432/{{ vault_postgres_file_pod_api_database }}"
vault_file_pod_api_jwt_secret: "your-super-secret-jwt-key-change-in-production-at-least-32-chars"
# OAuth Configuration
vault_file_pod_api_google_client_id: "your-google-client-id"
vault_file_pod_api_github_client_id: "your-github-client-id"
vault_file_pod_api_github_client_secret: "your-github-client-secret"

# ============================================================================
# Application: Personal Portofolio (Next.js)
# ============================================================================
# No specific environment variables needed - static site

# ============================================================================
# Application: Ruang Tenang API (Go Gin)
# ============================================================================
vault_ruang_tenang_api_db_host: "postgres-db"
vault_ruang_tenang_api_db_port: "5432"
vault_ruang_tenang_api_db_name: "{{ vault_postgres_ruang_tenang_api_database }}"
vault_ruang_tenang_api_db_user: "{{ vault_postgres_ruang_tenang_api_username }}"
vault_ruang_tenang_api_db_password: "{{ vault_postgres_ruang_tenang_api_password }}"
vault_ruang_tenang_api_jwt_secret: "your-super-secret-jwt-key-change-in-production-at-least-32-chars"
# AI Chat (Gemini API)
vault_ruang_tenang_api_gemini_api_key: "your-gemini-api-key"

# ============================================================================
# Application: Ruang Tenang Web (Next.js)
# ============================================================================
vault_ruang_tenang_web_api_url: "https://ruang-tenang-api.alfian-gading.site/api"

# ============================================================================
# Application: File Pod Mobile (Flutter)
# ============================================================================
# GitHub repository variable for CI/CD build
vault_file_pod_mobile_base_url: "https://file-pod-api.alfian-gading.site"
