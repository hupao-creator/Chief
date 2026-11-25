package model

import "encoding/json"

type ThinkingChoice struct {
	Mode   string `json:"mode"`
	Effort string `json:"effort,omitempty"`
}
type ThinkingCapability struct {
	Kind       string   `json:"kind"`
	Efforts    []string `json:"efforts,omitempty"`
	CanDisable bool     `json:"canDisable,omitempty"`
	Reason     string   `json:"reason,omitempty"`
}
type Worktree struct {
	Cwd        string `json:"cwd"`
	RemovedCwd string `json:"removedCwd,omitempty"`
}
type WorktreeOptions struct {
	Enabled *bool  `json:"enabled,omitempty"`
	Name    string `json:"name,omitempty"`
}

// SessionRecord's native state/settings are never projected by the host. In a
// catalog ThreadRecord, SessionState is the owning adapter's bounded overview;
// durable SessionRecord storage retains the complete native session.
type SessionRecord struct {
	ID               string            `json:"id"`
	HarnessID        string            `json:"harnessId"`
	Revision         int64             `json:"revision"`
	SessionState     json.RawMessage   `json:"sessionState"`
	Observation      PublicObservation `json:"observation"`
	Cwd              string            `json:"cwd"`
	Worktree         *Worktree         `json:"worktree,omitempty"`
	Settings         json.RawMessage   `json:"settings"`
	SettingsRevision int64             `json:"settingsRevision"`
	// CancellationID identifies the admission generation, including native opening
	// before an execution ID exists. It remains stable for the admitted execution.
	CancellationID string `json:"cancellationId,omitempty"`
	PendingInput   bool   `json:"pendingInput,omitempty"`
	CreatedAt      int64  `json:"createdAt"`
	UpdatedAt      int64  `json:"updatedAt"`
}

type ThreadRecord struct {
	SessionRecord
	// DirectoryTag and DirectoryScope are host-derived presentation metadata.
	// The runtime fills them on public projection, never from client filesystem state.
	DirectoryTag     string            `json:"directoryTag"`
	DirectoryScope   string            `json:"directoryScope"`
	Title            string            `json:"title"`
	ExecutionTitles  map[string]string `json:"executionTitles,omitempty"`
	MetadataState    json.RawMessage   `json:"metadataState,omitempty"`
	MetadataRevision *int64            `json:"metadataRevision,omitempty"`
	TagEmojis        map[string]string `json:"tagEmojis"`
	Tags             []string          `json:"tags"`
	Archived         *bool             `json:"archived,omitempty"`
	Moku             bool              `json:"moku,omitempty"`
	MokuHistory      bool              `json:"mokuHistory,omitempty"`
	Transcript       []json.RawMessage `json:"transcript,omitempty"`
	// Retain classification history when restoration or pool edits clear Tags.
	HadSemanticTag bool `json:"hadSemanticTag,omitempty"`
	// Only a successful Moku interrupt tool call supplies this exact execution ID.
	// Absence is unknown provenance, never evidence of a tool interruption.
	MokuInterruptedExecutionID string `json:"mokuInterruptedExecutionId,omitempty"`
	// Only an acknowledged user Stop supplies this exact execution ID.
	UserInterruptedExecutionID string `json:"userInterruptedExecutionId,omitempty"`
}

func (t *ThreadRecord) SetSemanticTags(tags []string, emojis map[string]string) {
	if len(t.Tags) > 0 && len(tags) == 0 {
		t.HadSemanticTag = true
	}
	t.Tags, t.TagEmojis = tags, emojis
}

type ThreadRef struct {
	ThreadID string `json:"threadId"`
	TypeID   string `json:"typeId"`
}
type ExecutionRef struct {
	Thread      ThreadRef `json:"thread"`
	ExecutionID string    `json:"executionId"`
}
type VersionedRecord struct {
	ID        string          `json:"id"`
	Revision  int64           `json:"revision"`
	CreatedAt int64           `json:"createdAt"`
	UpdatedAt int64           `json:"updatedAt"`
	Value     json.RawMessage `json:"value"`
}
type ApplicationThreadRecord struct {
	VersionedRecord
	Ref ThreadRef `json:"ref"`
}
type TagProjection struct {
	TagEmojis     map[string]string `json:"tagEmojis"`
	Tags          []string          `json:"tags"`
	SemanticTags  []string          `json:"semanticTags"`
	DirectoryTags []string          `json:"directoryTags"`
}
type ThreadPresentation struct {
	ID            string          `json:"id"`
	APIVersion    int             `json:"apiVersion"`
	SchemaVersion int             `json:"schemaVersion"`
	Value         json.RawMessage `json:"value"`
}
type ApplicationThread struct {
	Scope         string               `json:"scope,omitempty"`
	ID            string               `json:"id"`
	Ref           ThreadRef            `json:"ref"`
	Revision      int64                `json:"revision"`
	CreatedAt     int64                `json:"createdAt"`
	UpdatedAt     int64                `json:"updatedAt"`
	Title         string               `json:"title"`
	Archived      bool                 `json:"archived"`
	Tags          TagProjection        `json:"tags"`
	Presentations []ThreadPresentation `json:"presentations"`
	View          json.RawMessage      `json:"view"`
}

type Attachment struct {
	ID       string `json:"id"`
	Path     string `json:"path"`
	Name     string `json:"name"`
	MimeType string `json:"mimeType"`
	Size     int64  `json:"size"`
	Kind     string `json:"kind"`
}
type InputFile struct {
	ID       string `json:"id"`
	Path     string `json:"path,omitempty"`
	Name     string `json:"name,omitempty"`
	MimeType string `json:"mimeType,omitempty"`
	Size     int64  `json:"size,omitempty"`
}

// AgentInputPart covers the public discriminated input union. The host resolves
// File metadata before native I/O; client supplied paths are never authority.
type AgentInputPart struct {
	Kind         string     `json:"kind"`
	Text         string     `json:"text,omitempty"`
	AnnotationID string     `json:"annotationId,omitempty"`
	File         *InputFile `json:"file,omitempty"`
	URL          string     `json:"url,omitempty"`
	Detail       string     `json:"detail,omitempty"`
	Name         string     `json:"name,omitempty"`
	Path         string     `json:"path,omitempty"`
	PathType     string     `json:"pathType,omitempty"`
}
type AgentInput struct {
	Parts        []AgentInputPart `json:"parts"`
	Annotations  json.RawMessage  `json:"annotations,omitempty"`
	Presentation string           `json:"presentation,omitempty"`
}
type KnownDirectory struct {
	Name string `json:"name"`
	Path string `json:"path"`
}
