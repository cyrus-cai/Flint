#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Flint.xcodeproj')
project = Xcodeproj::Project.open(project_path)

flint_app_target = project.targets.find { |t| t.name == 'Flint' }
unless flint_app_target
  puts "ERROR: Flint target not found"
  exit 1
end

# Check if phase already exists
if flint_app_target.shell_script_build_phases.any? { |p| p.name == 'Embed FlintMCP' }
  puts "Embed FlintMCP build phase already exists, skipping."
  exit 0
end

# Add Run Script build phase
phase = flint_app_target.new_shell_script_build_phase('Embed FlintMCP')
phase.shell_path = '/bin/bash'
phase.input_paths = [
  '$(SRCROOT)/FlintMCP/dist/server.mjs',
]
phase.output_paths = [
  '$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Resources/FlintMCP/server.mjs',
]
phase.shell_script = <<~SCRIPT
  SRC="${SRCROOT}/FlintMCP/dist/server.mjs"
  if [ ! -f "$SRC" ]; then
    echo "warning: FlintMCP/dist/server.mjs not found, skipping. Run 'cd FlintMCP && bun run build' to enable."
    exit 0
  fi
  MCP_DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/FlintMCP"
  mkdir -p "$MCP_DEST"
  cp "$SRC" "$MCP_DEST/"
SCRIPT

puts "Added 'Embed FlintMCP' Run Script build phase to Flint target"

project.save
puts "Project saved successfully!"
