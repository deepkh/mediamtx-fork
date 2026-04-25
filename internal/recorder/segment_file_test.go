package recorder

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCreateSegmentFile(t *testing.T) {
	dir := t.TempDir()
	basePath := filepath.Join(dir, "segments", "cam", "2026-04-25_10-20-30-123456.ts")

	path, fi, err := createSegmentFile(basePath)
	require.NoError(t, err)
	require.Equal(t, basePath, path)
	fi.Close()

	_, err = os.Stat(basePath)
	require.NoError(t, err)
}

func TestCreateSegmentFileExisting(t *testing.T) {
	dir := t.TempDir()
	basePath := filepath.Join(dir, "segments", "cam", "2026-04-25_10-20-30-123456.ts")
	err := os.MkdirAll(filepath.Dir(basePath), 0o755)
	require.NoError(t, err)

	err = os.WriteFile(basePath, []byte("existing"), 0o644)
	require.NoError(t, err)

	path, fi, err := createSegmentFile(basePath)
	require.NoError(t, err)
	require.Equal(t, filepath.Join(dir, "segments", "cam", "2026-04-25_10-20-30-123456_1.ts"), path)
	fi.Close()

	contents, err := os.ReadFile(basePath)
	require.NoError(t, err)
	require.Equal(t, []byte("existing"), contents)
}

func TestCreateSegmentFileExistingMultiple(t *testing.T) {
	dir := t.TempDir()
	basePath := filepath.Join(dir, "2026-04-25_10-20-30-123456.ts")

	err := os.WriteFile(basePath, nil, 0o644)
	require.NoError(t, err)

	err = os.WriteFile(filepath.Join(dir, "2026-04-25_10-20-30-123456_1.ts"), nil, 0o644)
	require.NoError(t, err)

	path, fi, err := createSegmentFile(basePath)
	require.NoError(t, err)
	require.Equal(t, filepath.Join(dir, "2026-04-25_10-20-30-123456_2.ts"), path)
	fi.Close()
}
