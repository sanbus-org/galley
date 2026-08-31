// Command benchmark reports JSON throughput through the Galley Go bindings:
// no AST, no procedures, no error recovery. Parses
// languages/json/samples/code-01.json 50,000 times on one session and reports
// bytes/s.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"time"

	galley "github.com/sanbus-org/galley/examples/go/benchmark/galley"
)

const (
	logicalInput      = "languages/json/samples/code-01.json"
	defaultIterations = 50000
)

//go:generate go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen .

func resolveInput(explicit string) string {
	if explicit != "" {
		return explicit
	}
	if checkout := os.Getenv("GALLEY_CHECKOUT"); checkout != "" {
		candidate := filepath.Join(checkout, logicalInput)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	_, file, _, ok := runtime.Caller(0)
	if ok {
		candidate := filepath.Join(filepath.Dir(file), "..", "..", "..", logicalInput)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return filepath.Join("..", "..", logicalInput)
}

func main() {
	iterations := defaultIterations
	explicit := ""
	if len(os.Args) > 1 {
		explicit = os.Args[1]
	}
	if len(os.Args) > 2 {
		count, err := strconv.Atoi(os.Args[2])
		if err != nil || count < 1 {
			fmt.Fprintf(os.Stderr, "iterations must be >= 1\n")
			os.Exit(1)
		}
		iterations = count
	}

	path := resolveInput(explicit)
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read %s\n", logicalInput)
		os.Exit(1)
	}
	text := string(data)

	session, err := galley.New()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create a parser session\n")
		os.Exit(1)
	}
	defer session.Close()

	parsed, err := session.ParseSentinel(text)
	if err != nil || parsed != len(data) {
		if err != nil {
			fmt.Fprintf(os.Stderr, "warmup parse failed: %v\n", err)
		} else {
			fmt.Fprintf(os.Stderr, "warmup parse failed: parsed %d of %d bytes\n", parsed, len(data))
		}
		os.Exit(1)
	}

	start := time.Now()
	for index := 0; index < iterations; index++ {
		parsed, err = session.ParseSentinel(text)
		if err != nil || parsed != len(data) {
			if err != nil {
				fmt.Fprintf(os.Stderr, "parse failed at iteration %d: %v\n", index, err)
			} else {
				fmt.Fprintf(os.Stderr, "parse failed at iteration %d: parsed %d of %d bytes\n", index, parsed, len(data))
			}
			os.Exit(1)
		}
	}
	elapsed := time.Since(start).Nanoseconds()
	total := uint64(len(data)) * uint64(iterations)
	var bps uint64
	if elapsed > 0 {
		bps = total * 1000000000 / uint64(elapsed)
	}

	fmt.Printf("input: %s\n", logicalInput)
	fmt.Printf("bytes: %s\n", withThousands(uint64(len(data))))
	fmt.Printf("iterations: %s\n", withThousands(uint64(iterations)))
	fmt.Printf("parsed_bytes: %s\n", withThousands(total))
	fmt.Printf("duration_ns: %s\n", withThousands(uint64(elapsed)))
	fmt.Printf("bytes_per_second: %s\n", withThousands(bps))
}

func withThousands(n uint64) string {
	digits := strconv.FormatUint(n, 10)
	var b []byte
	for i := 0; i < len(digits); i++ {
		if i > 0 && (len(digits)-i)%3 == 0 {
			b = append(b, ',')
		}
		b = append(b, digits[i])
	}
	return string(b)
}
