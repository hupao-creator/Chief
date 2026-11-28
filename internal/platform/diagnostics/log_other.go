//go:build !darwin || !cgo

package diagnostics

func emit(string) {}

func isDevelopmentBundle(string) bool { return false }
