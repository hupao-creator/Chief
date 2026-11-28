//go:build darwin && cgo

package diagnostics

/*
#cgo LDFLAGS: -framework CoreFoundation
#include <CoreFoundation/CoreFoundation.h>
#include <os/log.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static int chief_development_bundle(const char *path) {
	CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
		(const UInt8 *)path, strlen(path), true);
	if (!url) return 0;
	CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, url);
	CFRelease(url);
	if (!bundle) return 0;
	CFStringRef identifier = CFBundleGetIdentifier(bundle);
	int matches = identifier && CFEqual(identifier, CFSTR("com.mokusei.native.dev"));
	CFRelease(bundle);
	return matches;
}

static os_log_t chief_log;
static pthread_once_t chief_log_once = PTHREAD_ONCE_INIT;

static void chief_create_log(void) {
	chief_log = os_log_create("com.mokusei.native.dev.diagnostics", "runtime");
}

static void chief_diagnostic(const char *event) {
	pthread_once(&chief_log_once, chief_create_log);
	os_log_with_type(chief_log, OS_LOG_TYPE_DEFAULT, "%{public}s", event);
}
*/
import "C"

import "unsafe"

func isDevelopmentBundle(path string) bool {
	value := C.CString(path)
	defer C.free(unsafe.Pointer(value))
	return C.chief_development_bundle(value) != 0
}

func emit(event string) {
	value := C.CString(event)
	defer C.free(unsafe.Pointer(value))
	C.chief_diagnostic(value)
}
