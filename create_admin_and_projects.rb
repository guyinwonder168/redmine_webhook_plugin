# Redmine Database Seeds - Admin User and Dummy Projects for Webhook Testing

# Check/Create admin user (needed for Rails 8.0 since db:schema:load doesn't create it)
puts "Checking admin user..."
admin_user = User.find_by(login: "admin")
if admin_user
  puts "Admin user already exists (login: #{admin_user.login})"
else
  puts "Creating admin user..."
  admin_user = User.create!(
    login: "admin",
    password: "admin1234",
    firstname: "Redmine",
    lastname: "Admin",
    mail: "admin@example.net",
    admin: true,
    status: User::STATUS_ACTIVE,
    language: "en",
    mail_notification: "only_my_events"
  )
  puts "Created admin user (login: admin, password: admin1234)"
end

puts ""
puts "Creating dummy projects..."
projects_data = [
  { name: "Marketing Website", identifier: "marketing-web", description: "Company marketing website and landing pages" },
  { name: "Mobile App", identifier: "mobile-app", description: "iOS and Android mobile application" },
  { name: "API Services", identifier: "api-services", description: "REST API endpoints and microservices" },
  { name: "Internal Tools", identifier: "internal-tools", description: "Developer tools and dashboards" },
  { name: "Documentation", identifier: "docs", description: "Project documentation and wikis" }
]

projects_data.each do |proj_data|
  Project.create!(
    name: proj_data[:name],
    identifier: proj_data[:identifier],
    description: proj_data[:description],
    is_public: true,
    status: Project::STATUS_ACTIVE
  )
  puts "Created: #{proj_data[:name]}"
end

puts ""
puts "Default data seeded successfully!"
puts "Total projects: #{Project.count}"
puts ""
puts "Projects available for webhook filtering:"
Project.all.each { |p| puts "  - #{p.name} (#{p.identifier})" }
