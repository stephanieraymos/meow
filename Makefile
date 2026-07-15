.PHONY: ship gen build profile

# Build, sign, and upload a new build to TestFlight.
ship:
	./scripts/upload-testflight.sh

# Regenerate the Xcode project from project.yml.
gen:
	xcodegen generate

# Build for the simulator (sanity check).
build: gen
	xcodebuild -project Meowdoku.xcodeproj -scheme Meowdoku \
	  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
	  -configuration Debug build

# (Re)mint the App Store distribution profile.
profile:
	python3 scripts/mint-profile.py
