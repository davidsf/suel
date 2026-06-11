# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.

# Default admin user. Override credentials via env vars outside development.
email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
password = ENV.fetch("ADMIN_PASSWORD", "password")

user = User.find_or_initialize_by(email_address: email)
user.update!(password: password, admin: true)
puts "Admin user: #{email}"
