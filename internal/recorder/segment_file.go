package recorder

import (
	"fmt"
	"os"
	"path/filepath"
)

const segmentFileMaxAttempts = 1000000

func createSegmentFile(path string) (string, *os.File, error) {
	err := os.MkdirAll(filepath.Dir(path), 0o755)
	if err != nil {
		return "", nil, err
	}

	for i := 0; i <= segmentFileMaxAttempts; i++ {
		curPath := path
		if i > 0 {
			ext := filepath.Ext(path)
			curPath = path[:len(path)-len(ext)] + fmt.Sprintf("_%d", i) + ext
		}

		fi, err := os.OpenFile(curPath, os.O_RDWR|os.O_CREATE|os.O_EXCL, 0o666)
		if err == nil {
			return curPath, fi, nil
		}

		if !os.IsExist(err) {
			return "", nil, err
		}
	}

	return "", nil, fmt.Errorf("all segment file names from %s to postfix _%d already exist", path, segmentFileMaxAttempts)
}
