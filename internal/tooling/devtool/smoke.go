package devtool

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
)

// Smoke validates the signed bundle without launching its runtime.
func Smoke(ctx context.Context, repo, application, channel, report string) error {
	if err := platform(); err != nil {
		return err
	}
	product, err := ProductConfiguration(channel)
	if err != nil {
		return err
	}
	application, err = filepath.Abs(application)
	if err != nil {
		return err
	}
	signature, err := verifySignature(ctx, application, product.BundleIdentifier, "", product.Channel == "alpha")
	if err != nil {
		return err
	}
	binary := filepath.Join(application, "Contents/MacOS/chief-runtime")
	runtimeSignature, err := verifySignature(ctx, binary, product.BundleIdentifier+".runtime", signature.Team, product.Channel == "alpha")
	if err != nil {
		return err
	}
	frameworks := filepath.Join(application, "Contents/Frameworks")
	framework := filepath.Join(frameworks, voiceFrameworkName)
	frameworkSignature, err := verifySignature(ctx, framework, voiceFrameworkIdentifier, signature.Team, product.Channel == "alpha")
	if err != nil {
		return err
	}
	if _, err := assertPortableMachO(ctx, filepath.Join(framework, "LiveKitWebRTC"), "", false); err != nil {
		return err
	}
	deps, err := assertPortableMachO(ctx, filepath.Join(application, "Contents/MacOS/Chief"), frameworks, false)
	if err != nil {
		return err
	}
	if !slices.Contains(deps, voiceFrameworkDependency) {
		return fmt.Errorf("missing embedded voice framework linkage")
	}
	entitlements, err := run(ctx, repo, nil, "/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", application)
	if err != nil {
		return err
	}
	signedEntitlements := bytes.Join(bytes.Fields([]byte(entitlements)), nil)
	if !bytes.Contains(signedEntitlements, []byte("<key>com.apple.security.device.audio-input</key><true/>")) {
		return fmt.Errorf("signed application is missing the microphone entitlement")
	}
	teamException := bytes.Contains(signedEntitlements, []byte("<key>com.apple.security.cs.disable-library-validation</key><true/>"))
	if teamException != (product.Channel == "alpha") {
		return fmt.Errorf("unexpected team library validation policy for %s", product.Channel)
	}
	if _, err = assertPortableMachO(ctx, binary, "", false); err != nil {
		return err
	}
	rpaths, err := machORPaths(ctx, filepath.Join(application, "Contents/MacOS/Chief"))
	if err != nil {
		return err
	}
	hasEmbedded := false
	for _, path := range rpaths {
		if !portableRPath(path) {
			return fmt.Errorf("nonportable framework search path %s", path)
		}
		if path == "@executable_path/../Frameworks" {
			hasEmbedded = true
		}
	}
	if !hasEmbedded {
		return fmt.Errorf("missing embedded Frameworks rpath")
	}
	if err = validatePackagedResources(application); err != nil {
		return err
	}
	for _, path := range []string{"Contents/MacOS/node", "Contents/Resources/native-renderer", "Contents/Resources/runtime/runtime.js", "Contents/Resources/node-provenance.json"} {
		if exists(filepath.Join(application, path)) {
			return fmt.Errorf("unexpected legacy Node artifact %s", path)
		}
	}
	out, err := run(ctx, repo, nil, "/usr/bin/plutil", "-convert", "json", "-o", "-", filepath.Join(application, "Contents/Info.plist"))
	if err != nil {
		return err
	}
	var info map[string]any
	if err = json.Unmarshal([]byte(out), &info); err != nil {
		return err
	}
	expected := map[string]string{
		"CFBundleIdentifier":           product.BundleIdentifier,
		"CFBundleName":                 product.DisplayName,
		"CFBundleDisplayName":          product.DisplayName,
		"CFBundleDevelopmentRegion":    "en",
		"ChiefDataDirectoryName":       product.DataDirectoryName,
		"LSMinimumSystemVersion":       "26.0",
		"CFBundleExecutable":           "Chief",
		"NSMicrophoneUsageDescription": "Chief uses your microphone when you start Voice Mode.",
	}
	for key, value := range expected {
		if info[key] != value {
			return fmt.Errorf("unexpected bundle metadata %s", key)
		}
	}
	localizations, ok := info["CFBundleLocalizations"].([]any)
	if !ok || len(localizations) != 2 || localizations[0] != "en" || localizations[1] != "zh-Hans" {
		return fmt.Errorf("unexpected bundle localizations")
	}
	if product.Channel == "alpha" {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		for _, name := range []string{"Chief", "chief-runtime"} {
			data, err := os.ReadFile(filepath.Join(application, "Contents/MacOS", name))
			if err != nil {
				return err
			}
			for _, path := range []string{repo, home} {
				if bytes.Contains(data, []byte(filepath.Clean(path)+"/")) {
					return fmt.Errorf("%s contains a local build path", name)
				}
			}
		}
	}
	result := map[string]any{"application": application, "signature": signature, "runtimeSignature": runtimeSignature, "nodeFree": true, "headless": os.Getenv("CHIEF_HEADLESS") == "1", "scope": "Signed bundle, portable Go and Swift binaries, and packaged resources. No application processes are launched."}
	result["voiceFrameworkSignature"] = frameworkSignature
	result["signedAudioInput"] = true
	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	if report != "" {
		if err = os.WriteFile(report, append(data, '\n'), 0600); err != nil {
			return err
		}
	}
	fmt.Println(string(data))
	return nil
}
