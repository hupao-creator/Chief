package devtool

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Ad-hoc binaries have no Team ID. Replace team-based library validation on
// Alpha with a load constraint for the exact signed framework. macOS always
// admits its operating system libraries.
func alphaVoiceConstraint(ctx context.Context, staging, framework string) (string, error) {
	out, err := combined(ctx, "/usr/bin/codesign", "-d", "--verbose=4", framework)
	if err != nil {
		return "", err
	}
	match := regexp.MustCompile(`(?m)^CDHash=([a-f0-9]{40})$`).FindStringSubmatch(out)
	if match == nil {
		return "", fmt.Errorf("cannot read the signed voice framework's code directory hash")
	}
	hash, err := hex.DecodeString(match[1])
	if err != nil {
		return "", err
	}
	path := filepath.Join(staging, "alpha-library-constraint.plist")
	plist := "<plist version=\"1.0\"><dict><key>cdhash</key><data>" + base64.StdEncoding.EncodeToString(hash) + "</data></dict></plist>"
	return path, os.WriteFile(path, []byte(plist), 0600)
}

func stageVoiceFramework(ctx context.Context, repo, frameworks, resources string) (string, error) {
	artifact := filepath.Join(repo, "app/macos/.build/artifacts/webrtc-xcframework/LiveKitWebRTC/LiveKitWebRTC.xcframework")
	out, err := run(ctx, repo, nil, "/usr/bin/plutil", "-convert", "json", "-o", "-", filepath.Join(artifact, "Info.plist"))
	if err != nil {
		return "", err
	}
	var info struct {
		AvailableLibraries []struct {
			LibraryIdentifier, LibraryPath, SupportedPlatform, SupportedPlatformVariant string
			SupportedArchitectures                                                      []string
		}
	}
	if err = json.Unmarshal([]byte(out), &info); err != nil {
		return "", err
	}
	var source string
	for _, lib := range info.AvailableLibraries {
		if lib.SupportedPlatform != "macos" || lib.SupportedPlatformVariant != "" || lib.LibraryPath != voiceFrameworkName {
			continue
		}
		for _, arch := range lib.SupportedArchitectures {
			if arch == "arm64" {
				source = filepath.Join(artifact, lib.LibraryIdentifier, lib.LibraryPath)
			}
		}
	}
	if source == "" {
		return "", fmt.Errorf("SwiftPM has no matching macOS arm64 WebRTC framework")
	}
	if _, err = assertPortableMachO(ctx, filepath.Join(source, "LiveKitWebRTC"), "", true); err != nil {
		return "", err
	}
	if err = os.MkdirAll(frameworks, 0755); err != nil {
		return "", err
	}
	destination := filepath.Join(frameworks, voiceFrameworkName)
	if _, err = run(ctx, repo, nil, "/usr/bin/ditto", source, destination); err != nil {
		return "", err
	}
	binary, err := filepath.EvalSymlinks(filepath.Join(destination, "LiveKitWebRTC"))
	if err != nil {
		return "", err
	}
	out, err = run(ctx, repo, nil, "/usr/bin/lipo", "-archs", binary)
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(out) != "arm64" {
		if _, err = run(ctx, repo, nil, "/usr/bin/lipo", binary, "-thin", "arm64", "-output", binary+".arm64"); err != nil {
			return "", err
		}
		if err = os.Rename(binary+".arm64", binary); err != nil {
			return "", err
		}
	}
	if _, err = assertPortableMachO(ctx, binary, "", false); err != nil {
		return "", err
	}
	if err = copyFile(filepath.Join(artifact, "LICENSE"), filepath.Join(resources, "licenses/LiveKitWebRTC-LICENSE"), 0644); err != nil {
		return "", err
	}
	return destination, nil
}
