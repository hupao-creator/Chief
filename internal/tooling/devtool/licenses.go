package devtool

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

// Collect notices from the same dependency checkouts used to build the app.
func packageLicenses(ctx context.Context, repo, directory string) error {
	goroot, err := run(ctx, repo, nil, goExecutable(), "env", "GOROOT")
	if err != nil {
		return err
	}
	if err = copyFile(filepath.Join(strings.TrimSpace(goroot), "LICENSE"), filepath.Join(directory, "Go-LICENSE"), 0644); err != nil {
		return err
	}
	if err = copyFile(filepath.Join(repo, "LICENSE"), filepath.Join(directory, "Chief-LICENSE"), 0644); err != nil {
		return err
	}

	var notices bytes.Buffer
	appendNotice := func(component, source string) error {
		data, err := os.ReadFile(source)
		if err != nil {
			return err
		}
		fmt.Fprintf(&notices, "%s — %s\n\n", component, filepath.Base(source))
		notices.Write(bytes.TrimSpace(data))
		notices.WriteString("\n\n")
		return nil
	}
	if err = appendNotice("Unicode", filepath.Join(repo, "internal/services/taglabel/UNICODE-LICENSE.txt")); err != nil {
		return err
	}
	list, err := run(ctx, repo, nil, goExecutable(), "list", "-deps", "-f", `{{with .Module}}{{if not .Main}}{{.Path}}{{"\t"}}{{.Dir}}{{end}}{{end}}`, "./cmd/chief-runtime")
	if err != nil {
		return err
	}
	modules := strings.Split(strings.TrimSpace(list), "\n")
	slices.Sort(modules)
	for _, module := range slices.Compact(modules) {
		name, root, ok := strings.Cut(module, "\t")
		if !ok {
			return fmt.Errorf("missing module directory for packaged Go notices")
		}
		if err = appendNotice(name, filepath.Join(root, "LICENSE")); err != nil {
			return err
		}
		if err = appendNotice(name, filepath.Join(root, "NOTICE")); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	checkouts := filepath.Join(repo, "app/macos/.build/checkouts")
	for _, file := range []string{"swift-cmark/COPYING", "swift-markdown/LICENSE.txt", "swift-markdown/NOTICE.txt", "swift-system/LICENSE.txt", "swift-url/LICENSE", "swift-url/NOTICE"} {
		if err = appendNotice(filepath.Dir(file), filepath.Join(checkouts, file)); err != nil {
			return err
		}
	}
	return os.WriteFile(filepath.Join(directory, "ThirdPartyNotices.txt"), notices.Bytes(), 0644)
}
