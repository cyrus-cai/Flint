#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.join(__dir__, '..', 'Flint.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Check if target already exists
if project.targets.any? { |t| t.name == 'flint-cli' }
  puts "flint-cli target already exists, skipping."
  exit 0
end

# 1. Add swift-argument-parser SPM dependency
arg_parser_ref = project.root_object.package_references.find { |r| r.repositoryURL&.include?('swift-argument-parser') }
unless arg_parser_ref
  arg_parser_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  arg_parser_ref.repositoryURL = 'https://github.com/apple/swift-argument-parser'
  arg_parser_ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '1.5.0' }
  project.root_object.package_references << arg_parser_ref
  puts "Added swift-argument-parser SPM reference"
end

# 2. Create the CLI target
cli_target = project.new_target(:command_line_tool, 'flint-cli', :osx, '14.6', nil, :swift)
puts "Created flint-cli target"

# 3. Add ArgumentParser package product dependency to CLI target
arg_parser_dep = cli_target.package_product_dependencies.find { |d| d.product_name == 'ArgumentParser' }
unless arg_parser_dep
  arg_parser_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  arg_parser_dep.product_name = 'ArgumentParser'
  arg_parser_dep.package = arg_parser_ref
  cli_target.package_product_dependencies << arg_parser_dep

  # Also add to frameworks build phase
  frameworks_phase = cli_target.frameworks_build_phase
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = arg_parser_dep
  frameworks_phase.files << build_file
  puts "Linked ArgumentParser to flint-cli"
end

# 4. Create FlintCLI group in project
main_group = project.main_group
cli_group = main_group.find_subpath('FlintCLI', false)
unless cli_group
  cli_group = main_group.new_group('FlintCLI', 'FlintCLI')
end

commands_group = cli_group.find_subpath('Commands', false)
unless commands_group
  commands_group = cli_group.new_group('Commands', 'Commands')
end

helpers_group = cli_group.find_subpath('Helpers', false)
unless helpers_group
  helpers_group = cli_group.new_group('Helpers', 'Helpers')
end

# 5. Add FlintCLI source files
cli_files = {
  cli_group => ['main.swift', 'CLIVersion.swift'],
  commands_group => [
    'CreateCommand.swift',
    'ListCommand.swift',
    'SearchCommand.swift',
    'ReadCommand.swift',
    'EditCommand.swift',
    'RemoveCommand.swift',
    'StatusCommand.swift',
  ],
  helpers_group => ['NoteResolver.swift'],
}

cli_files.each do |group, files|
  files.each do |file|
    basename = File.basename(file)
    ref = group.find_file_by_path(basename)
    unless ref
      ref = group.new_file(file)
    end
    cli_target.source_build_phase.add_file_reference(ref) unless cli_target.source_build_phase.files.any? { |f| f.file_ref == ref }
  end
end
puts "Added FlintCLI source files"

# 6. Add shared files (FileManagerExtend.swift, AutoUpdate.swift) to CLI target
flint_group = main_group.find_subpath('Flint', false)
utils_group = flint_group.find_subpath('Utils', false)

['FileManagerExtend.swift', 'AutoUpdate.swift'].each do |filename|
  ref = utils_group.find_file_by_path(filename)
  if ref
    cli_target.source_build_phase.add_file_reference(ref) unless cli_target.source_build_phase.files.any? { |f| f.file_ref == ref }
    puts "Added #{filename} to flint-cli target"
  else
    puts "WARNING: #{filename} not found in Utils group"
  end
end

# 7. Configure build settings for CLI target
cli_target.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.6'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['PRODUCT_NAME'] = 'flint-cli'
  config.build_settings['DEAD_CODE_STRIPPING'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = '32RM54L485'
  config.build_settings['MARKETING_VERSION'] = '0.9.7'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
end
puts "Configured flint-cli build settings"

# 8. Add flint-cli as dependency of Flint app target + Copy Files build phase
flint_app_target = project.targets.find { |t| t.name == 'Flint' }
if flint_app_target
  # Add target dependency
  flint_app_target.add_dependency(cli_target)
  puts "Added flint-cli as dependency of Flint"

  # Add Copy Files build phase to embed CLI binary in Resources
  copy_phase = flint_app_target.new_copy_files_build_phase('Embed CLI')
  copy_phase.dst_subfolder_spec = '7' # Resources
  cli_product_ref = cli_target.product_reference
  build_file = copy_phase.add_file_reference(cli_product_ref)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "Added Copy Files phase to embed flint-cli in app Resources"
end

# 9. Add TargetAttributes for the new CLI target
attrs = project.root_object.attributes['TargetAttributes'] || {}
attrs[cli_target.uuid] = { 'CreatedOnToolsVersion' => '16.0' }
project.root_object.attributes['TargetAttributes'] = attrs

project.save
puts "Project saved successfully!"
