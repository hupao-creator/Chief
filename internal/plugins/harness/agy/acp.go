// Package agy connects to the installed Antigravity CLI over ACP stdio.
package agy

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/hupao-creator/Chief/internal/core/plugin"
	"github.com/hupao-creator/Chief/internal/platform/processgroup"
)

type object = map[string]any
type frame struct {
	Version string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
	Result  json.RawMessage `json:"result"`
	Error   *struct {
		Code int `json:"code"`
	} `json:"error"`
}

// A client has one request reader. Interrupt and permission responses may write
// concurrently. Native stderr and non-protocol stdout can contain sign-in URLs.
type client struct {
	cmd       *exec.Cmd
	in        io.WriteCloser
	out       io.ReadCloser
	scanner   *bufio.Scanner
	writeMu   sync.Mutex
	seq       int
	mu        sync.Mutex
	pending   *request
	done      chan struct{}
	readErr   error
	path      string
	geminiDir string
	canClose  bool
}

func start(ctx context.Context, host plugin.HostContext, cwd string) (*client, error) {
	path, err := host.ResolveExecutable(ctx, "agy", cwd, "")
	if err != nil {
		return nil, err
	}
	env, err := host.Environment(ctx)
	if err != nil {
		return nil, err
	}
	cmd := exec.Command(path, "acp", "--stdio")
	cmd.Dir = cwd
	cmd.Env = []string{}
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	in, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		in.Close()
		return nil, err
	}

	if err = cmd.Start(); err != nil {
		in.Close()
		out.Close()
		return nil, err
	}
	scanner := bufio.NewScanner(out)
	scanner.Buffer(make([]byte, 65536), 8<<20)
	// Without --gemini-dir, agy uses the native home even when another
	// Google tool sets GEMINI_HOME in the parent environment.
	dir := filepath.Join(env["HOME"], ".gemini")
	if real, err := filepath.EvalSymlinks(dir); err == nil {
		dir = real
	}
	c := &client{geminiDir: dir, cmd: cmd, in: in, out: out, scanner: scanner, path: path, done: make(chan struct{})}
	go c.read()
	return c, nil
}
func (c *client) abort() { _ = c.cmd.Process.Kill(); c.out.Close(); c.in.Close() }
func (c *client) close() error {
	c.in.Close()
	c.out.Close()
	// EOF lets agy flush its native history before the next process resumes it.
	timer := time.AfterFunc(2*time.Second, func() { _ = c.cmd.Process.Kill() })
	_ = c.cmd.Wait()
	timer.Stop()
	<-c.done
	return processgroup.DrainAfterExit(c.cmd.Process.Pid)
}
func (c *client) write(msg object) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	// Permission replies share the writer with cancellation. Retire a peer
	// that stops consuming its pipe so neither can hold the thread indefinitely.
	deadline := time.AfterFunc(5*time.Second, c.abort)
	defer deadline.Stop()
	msg["jsonrpc"] = "2.0"
	return json.NewEncoder(c.in).Encode(msg)
}

type request struct {
	id      string
	method  string
	onFrame func(frame) error
	result  chan frame
}

func (c *client) send(method string, params object, onFrame func(frame) error) (*request, error) {
	c.mu.Lock()
	c.seq++
	seq := c.seq
	r := &request{id: fmt.Sprint(seq), method: method, onFrame: onFrame, result: make(chan frame, 1)}
	c.pending = r
	c.mu.Unlock()
	if err := c.write(object{"id": seq, "method": method, "params": params}); err != nil {
		return nil, err
	}
	return r, nil
}
func (c *client) call(method string, params object, result any) error {
	r, err := c.send(method, params, nil)
	if err != nil {
		return err
	}
	return c.response(r, result)
}
func (c *client) response(r *request, result any) error {
	var f frame
	select {
	case f = <-r.result:
	case <-c.done:
		select {
		case f = <-r.result:
		default:
			return c.readErr
		}
	}
	if f.Error != nil {
		if f.Error.Code == -32000 || r.method == "authenticate" {
			return fmt.Errorf("Antigravity authentication failed (ACP %d). Check your sign-in in agy and the authentication method in Chief Settings", f.Error.Code)
		}
		return fmt.Errorf("Antigravity %s failed (ACP error %d)", r.method, f.Error.Code)
	}
	if result == nil {
		return nil
	}
	return json.Unmarshal(f.Result, result)
}

// Keep draining stdio between prompts. Unsolicited permissions have no Chief
// execution owner and receive a cancelled outcome. A response ends its event
// window before the next request can be registered.
func (c *client) read() {
	defer close(c.done)
	for c.scanner.Scan() {
		var f frame
		if err := json.Unmarshal(c.scanner.Bytes(), &f); err != nil || f.Version != "2.0" {
			continue
		}
		c.mu.Lock()
		r := c.pending
		if f.Method == "" && r != nil && string(f.ID) == r.id {
			c.pending = nil
			r.result <- f
		}
		c.mu.Unlock()
		if f.Method == "" {
			continue
		}
		if r != nil && r.onFrame != nil {
			c.readErr = r.onFrame(f)
		} else if f.ID != nil {
			c.readErr = c.unsupported(f)
		}
		if c.readErr != nil {
			return
		}
	}
	c.readErr = c.scanner.Err()
	if c.readErr == nil {
		c.readErr = errors.New("Antigravity closed its ACP connection")
	}
}
func (c *client) unsupported(f frame) error {
	if f.Method == "session/request_permission" {
		return c.write(object{"id": f.ID, "result": object{"outcome": object{"outcome": "cancelled"}}})
	}
	return c.write(object{"id": f.ID, "error": object{"code": -32601, "message": "Unsupported client method"}})
}

type nativeModel struct {
	ID   string `json:"modelId"`
	Name string `json:"name"`
}

type catalog struct {
	ID     string `json:"sessionId"`
	Models struct {
		Current   string        `json:"currentModelId"`
		Available []nativeModel `json:"availableModels"`
	} `json:"models"`
	Modes struct {
		Current string `json:"currentModeId"`
	} `json:"modes"`
}

type authMethod struct {
	ID string `json:"id"`
}

type initialization struct {
	Version int `json:"protocolVersion"`
	Agent   struct {
		Name    string `json:"name"`
		Version string `json:"version"`
	} `json:"agentInfo"`
	Auth []authMethod `json:"authMethods"`
	Caps struct {
		Load     bool `json:"loadSession"`
		Sessions struct {
			Resume *struct{} `json:"resume"`
			Close  *struct{} `json:"close"`
		} `json:"sessionCapabilities"`
	} `json:"agentCapabilities"`
}

func (c *client) initialize() (initialization, error) {
	var info initialization
	if err := c.call("initialize", object{"protocolVersion": 1, "clientInfo": object{"name": "chief", "title": "Chief", "version": "1"}, "clientCapabilities": object{}}, &info); err != nil {
		return info, err
	}
	if info.Version != 1 || info.Agent.Name != "Antigravity ACP Server" {
		return info, errors.New("agy did not identify as the Antigravity ACP v1 server")
	}
	// Older releases restrict model access to a short list of editor identities.
	versionText := strings.TrimPrefix(info.Agent.Version, "agy_acp_server_")
	parts := strings.Split(strings.TrimPrefix(versionText, "v"), ".")
	var version []uint64
	for _, part := range parts {
		n, err := strconv.ParseUint(part, 10, 32)
		if err != nil {
			break
		}
		version = append(version, n)
	}
	if len(parts) != 3 || len(version) != 3 || slices.Compare(version, []uint64{1, 5, 1}) < 0 {
		return info, errors.New("Chief requires a stable Antigravity CLI version 1.5.1 or later")
	}
	c.canClose = info.Caps.Sessions.Close != nil
	return info, nil
}

func (c *client) session(info initialization, cwd, sessionID, methodID string) (catalog, error) {
	var cat catalog
	if methodID != "" {
		if !slices.ContainsFunc(info.Auth, func(method authMethod) bool { return method.ID == methodID }) {
			return cat, errors.New("this Antigravity CLI does not offer the selected authentication method")
		}
		if err := c.call("authenticate", object{"methodId": methodID}, nil); err != nil {
			return cat, err
		}
	}
	method := "session/new"
	params := object{"cwd": cwd, "mcpServers": []any{}}
	if sessionID != "" {
		switch {
		case info.Caps.Sessions.Resume != nil:
			method = "session/resume"
		case info.Caps.Load:
			method = "session/load"
		default:
			return cat, errors.New("Antigravity cannot reopen this session")
		}
		params["sessionId"] = sessionID
	}
	if err := c.call(method, params, &cat); err != nil {
		return cat, err
	}
	if sessionID != "" {
		if cat.ID != "" && cat.ID != sessionID {
			return cat, errors.New("Antigravity resumed another session")
		}
		cat.ID = sessionID
	}
	if cat.ID == "" {
		return cat, errors.New("Antigravity returned an empty session ID")
	}
	return cat, nil
}
