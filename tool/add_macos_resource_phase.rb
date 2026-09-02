# Adds the "Copy Dynamsoft Resources" build phase to the Runner target of a
# Flutter macOS example. DCV locates Templates/Models/ParserResources next to
# its dylibs, which live in Contents/Frameworks — but codesign rejects loose
# unsigned .data files there. The phase therefore copies the resources into
# Contents/Resources/dynamsoft (a codesign-safe location) and places symlinks
# in Contents/Frameworks, which DCV follows transparently.
#
# Usage: ruby tool/add_macos_resource_phase.rb path/to/macos/Runner.xcodeproj
require 'xcodeproj'

project_path = ARGV[0]
abort('usage: add_macos_resource_phase.rb <Runner.xcodeproj>') if project_path.nil?

SCRIPT_NAME = 'Copy Dynamsoft Resources'
SCRIPT_BODY = <<~SH
  RESOURCES_SRC="${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/flutter_capture_vision_macos/macos/flutter_capture_vision_macos/Resources"
  APP_RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/dynamsoft"
  APP_FRAMEWORKS="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
  if [ ! -d "$RESOURCES_SRC" ]; then
    echo "warning: Dynamsoft resources not found at $RESOURCES_SRC"
    exit 0
  fi
  mkdir -p "$APP_RESOURCES" "$APP_FRAMEWORKS"
  rsync -a --delete "$RESOURCES_SRC/" "$APP_RESOURCES/"
  for item in "$RESOURCES_SRC"/*; do
    name="$(basename "$item")"
    rm -rf "$APP_FRAMEWORKS/$name"
    ln -s "../Resources/dynamsoft/$name" "$APP_FRAMEWORKS/$name"
  done
SH

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort('Runner target not found') if runner.nil?

existing = runner.shell_script_build_phases.find { |phase| phase.name == SCRIPT_NAME }
phase = existing || runner.new_shell_script_build_phase(SCRIPT_NAME)
phase.shell_script = SCRIPT_BODY
phase.input_paths = ['${PODS_ROOT}/../Flutter/ephemeral/.symlinks/plugins/flutter_capture_vision_macos/macos/flutter_capture_vision_macos/Resources']
phase.output_paths = ['${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/dynamsoft']
project.save
puts "#{existing ? 'updated' : 'added'} '#{SCRIPT_NAME}' in #{project_path}"
