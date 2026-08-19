package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type server struct {
	root       string
	graphqlURL string
	client     *http.Client
	mu         sync.Mutex
	validated  map[[32]byte]time.Time
}

type fileItem struct {
	Name        string    `json:"name"`
	Path        string    `json:"path"`
	IsDirectory bool      `json:"isDirectory"`
	Size        int64     `json:"size"`
	ModifiedAt  time.Time `json:"modifiedAt"`
}

type pathBody struct { Path string `json:"path"` }
type transferBody struct {
	Source      string `json:"source"`
	Destination string `json:"destination"`
}

func main() {
	root := env("AW_ROOT", "/data")
	realRoot, err := filepath.EvalSymlinks(root)
	if err != nil { log.Fatal(err) }
	s := &server{
		root: realRoot, graphqlURL: env("UNRAID_GRAPHQL_URL", "http://127.0.0.1/graphql"),
		client: &http.Client{Timeout: 8 * time.Second}, validated: make(map[[32]byte]time.Time),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("GET /files", s.list)
	mux.HandleFunc("PUT /files", s.upload)
	mux.HandleFunc("DELETE /files", s.remove)
	mux.HandleFunc("GET /download", s.download)
	mux.HandleFunc("POST /directories", s.mkdir)
	mux.HandleFunc("POST /move", s.move)
	mux.HandleFunc("POST /copy", s.copy)
	address := env("AW_LISTEN", ":8089")
	log.Printf("AW Companion listening on %s, root %s", address, realRoot)
	log.Fatal(http.ListenAndServe(address, s.authenticate(mux)))
}

func (s *server) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := strings.TrimSpace(r.Header.Get("x-api-key"))
		if key == "" || !s.validateKey(key) { writeError(w, http.StatusUnauthorized, "API Key 无效或权限不足"); return }
		next.ServeHTTP(w, r)
	})
}

func (s *server) validateKey(key string) bool {
	hash := sha256.Sum256([]byte(key))
	s.mu.Lock(); expires, ok := s.validated[hash]; s.mu.Unlock()
	if ok && time.Now().Before(expires) { return true }
	body := []byte(`{"query":"query AWCompanionAuth { online }"}`)
	req, err := http.NewRequest(http.MethodPost, s.graphqlURL, bytes.NewReader(body))
	if err != nil { return false }
	req.Header.Set("Content-Type", "application/json"); req.Header.Set("x-api-key", key)
	response, err := s.client.Do(req)
	if err != nil { return false }
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 { return false }
	var result struct { Data map[string]any `json:"data"`; Errors []any `json:"errors"` }
	if json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&result) != nil || len(result.Errors) > 0 || result.Data == nil { return false }
	s.mu.Lock(); s.validated[hash] = time.Now().Add(time.Minute); s.mu.Unlock()
	return true
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) { writeJSON(w, http.StatusOK, map[string]string{"status": "ok"}) }

func (s *server) list(w http.ResponseWriter, r *http.Request) {
	full, virtual, err := s.resolve(r.URL.Query().Get("path"), true)
	if err != nil { writeError(w, http.StatusBadRequest, err.Error()); return }
	entries, err := os.ReadDir(full)
	if err != nil { writeFileError(w, err); return }
	items := make([]fileItem, 0, len(entries))
	for _, entry := range entries {
		info, err := entry.Info(); if err != nil { continue }
		items = append(items, fileItem{Name: entry.Name(), Path: joinVirtual(virtual, entry.Name()), IsDirectory: entry.IsDir(), Size: info.Size(), ModifiedAt: info.ModTime().UTC()})
	}
	writeJSON(w, http.StatusOK, items)
}

func (s *server) mkdir(w http.ResponseWriter, r *http.Request) {
	var body pathBody; if !decodeJSON(w, r, &body) { return }
	full, _, err := s.resolve(body.Path, false); if err != nil { writeError(w, 400, err.Error()); return }
	if err = os.Mkdir(full, 0755); err != nil { writeFileError(w, err); return }
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) upload(w http.ResponseWriter, r *http.Request) {
	full, _, err := s.resolve(r.URL.Query().Get("path"), false); if err != nil { writeError(w, 400, err.Error()); return }
	file, err := os.OpenFile(full, os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0644); if err != nil { writeFileError(w, err); return }
	ok := false; defer func() { file.Close(); if !ok { os.Remove(full) } }()
	if _, err = io.Copy(file, r.Body); err != nil { writeFileError(w, err); return }
	ok = true; w.WriteHeader(http.StatusCreated)
}

func (s *server) download(w http.ResponseWriter, r *http.Request) {
	full, _, err := s.resolve(r.URL.Query().Get("path"), true); if err != nil { writeError(w, 400, err.Error()); return }
	info, err := os.Stat(full); if err != nil { writeFileError(w, err); return }
	if info.IsDir() { writeError(w, 400, "不能直接下载文件夹"); return }
	http.ServeFile(w, r, full)
}

func (s *server) remove(w http.ResponseWriter, r *http.Request) {
	full, virtual, err := s.resolve(r.URL.Query().Get("path"), true); if err != nil { writeError(w, 400, err.Error()); return }
	if virtual == "/" { writeError(w, 403, "不能删除文件根目录"); return }
	if err = os.RemoveAll(full); err != nil { writeFileError(w, err); return }
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) move(w http.ResponseWriter, r *http.Request) {
	var body transferBody; if !decodeJSON(w, r, &body) { return }
	source, _, err := s.resolve(body.Source, true); if err != nil { writeError(w, 400, err.Error()); return }
	destination, _, err := s.resolve(body.Destination, false); if err != nil { writeError(w, 400, err.Error()); return }
	if err = os.Rename(source, destination); err != nil { writeFileError(w, err); return }
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) copy(w http.ResponseWriter, r *http.Request) {
	var body transferBody; if !decodeJSON(w, r, &body) { return }
	source, _, err := s.resolve(body.Source, true); if err != nil { writeError(w, 400, err.Error()); return }
	destination, _, err := s.resolve(body.Destination, false); if err != nil { writeError(w, 400, err.Error()); return }
	if err = copyPath(source, destination); err != nil { writeFileError(w, err); return }
	w.WriteHeader(http.StatusCreated)
}

func (s *server) resolve(value string, mustExist bool) (string, string, error) {
	virtual := "/" + strings.TrimPrefix(filepath.ToSlash(filepath.Clean("/"+value)), "/")
	full := filepath.Join(s.root, filepath.FromSlash(strings.TrimPrefix(virtual, "/")))
	check := full; if !mustExist { check = filepath.Dir(full) }
	real, err := filepath.EvalSymlinks(check); if err != nil { return "", "", err }
	rel, err := filepath.Rel(s.root, real); if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) { return "", "", errors.New("路径超出文件根目录") }
	return full, virtual, nil
}

func copyPath(source, destination string) error {
	info, err := os.Stat(source); if err != nil { return err }
	if info.IsDir() {
		if err = os.Mkdir(destination, info.Mode().Perm()); err != nil { return err }
		entries, err := os.ReadDir(source); if err != nil { return err }
		for _, entry := range entries { if err = copyPath(filepath.Join(source, entry.Name()), filepath.Join(destination, entry.Name())); err != nil { return err } }
		return nil
	}
	in, err := os.Open(source); if err != nil { return err }; defer in.Close()
	out, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, info.Mode().Perm()); if err != nil { return err }
	ok := false; defer func() { out.Close(); if !ok { os.Remove(destination) } }()
	_, err = io.Copy(out, in); ok = err == nil; return err
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(target); err != nil { writeError(w, 400, "请求内容无效"); return false }; return true
}
func writeFileError(w http.ResponseWriter, err error) { if os.IsNotExist(err) { writeError(w, 404, "文件不存在") } else if os.IsExist(err) { writeError(w, 409, "同名文件已存在") } else if os.IsPermission(err) { writeError(w, 403, "没有文件操作权限") } else { writeError(w, 500, err.Error()) } }
func writeError(w http.ResponseWriter, status int, message string) { writeJSON(w, status, map[string]string{"error": message}) }
func writeJSON(w http.ResponseWriter, status int, value any) { w.Header().Set("Content-Type", "application/json"); w.WriteHeader(status); _ = json.NewEncoder(w).Encode(value) }
func joinVirtual(parent, name string) string { if parent == "/" { return "/" + name }; return strings.TrimSuffix(parent, "/") + "/" + name }
func env(name, fallback string) string { if value := strings.TrimSpace(os.Getenv(name)); value != "" { return value }; return fallback }
