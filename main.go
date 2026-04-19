// main executable.
package main

import (
	"fmt"
	"os"

	"github.com/bluenviron/mediamtx/internal/core"
)

var buildCommit = "unknown"

func main() {
	fmt.Printf("=======================================\n")
	fmt.Printf("=== mediamtx commit: %s\n", buildCommit)
	fmt.Printf("=======================================\n")

	s, ok := core.New(os.Args[1:])
	if !ok {
		os.Exit(1)
	}
	s.Wait()
}
