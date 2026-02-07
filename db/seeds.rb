# Redmine Database Seeds - Dummy Projects for Webhook Testing

puts "Seeding dummy projects for webhook endpoint testing..."

# Create dummy projects
projects_data = [
  { name: "Marketing Website", identifier: "marketing-web", description: "Company marketing website and landing pages" },
  { name: "Mobile App", identifier: "mobile-app", description: "iOS and Android mobile application" },
  { name: "API Services", identifier: "api-services", description: "REST API endpoints and microservices" },
  { name: "Ops Tools", identifier: "ops-tools", description: "Developer tools and dashboards" },
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
  puts "  ✓ Created: #{proj_data[:name]}"
end

puts ""
puts "✓ Dummy projects seeded successfully!"
puts "Total projects: #{Project.count}"
puts ""
puts "Projects available for webhook filtering:"
Project.all.each { |p| puts "  - #{p.name} (#{p.identifier})" }
