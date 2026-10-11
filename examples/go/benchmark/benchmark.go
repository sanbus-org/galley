// Command benchmark reports parse throughput through the Galley Go
// bindings: parses the given sample on one session and reports bytes/s.
package main

import (
	"fmt"
	"os"
	"strconv"
	"time"

	galley "github.com/sanbus-org/galley/examples/go/benchmark/galley"
)

const defaultIterations = 10

//go:generate go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen .

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: benchmark <sample-file> [iterations]")
		os.Exit(1)
	}
	path := os.Args[1]
	iterations := defaultIterations
	if len(os.Args) > 2 {
		count, err := strconv.Atoi(os.Args[2])
		if err != nil || count < 1 {
			fmt.Fprintf(os.Stderr, "iterations must be >= 1\n")
			os.Exit(1)
		}
		iterations = count
	}

	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to read %s\n", path)
		os.Exit(1)
	}
	expected := len(data)

	session, err := galley.New()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create a parser session\n")
		os.Exit(1)
	}
	defer func() {
		if err := session.Close(); err != nil {
			fmt.Fprintf(os.Stderr, "close failed: %v\n", err)
		}
	}()

	// The first two parses are cold: the session arena grows during the first and is reallocated for the second.
	var parsed int
	for warmup := 0; warmup < 2; warmup++ {
		parsed, err = session.Parse(data)
		if err != nil || parsed != expected {
			if err != nil {
				fmt.Fprintf(os.Stderr, "warmup parse failed: %v\n", err)
			} else {
				fmt.Fprintf(os.Stderr, "warmup parse failed: parsed %d of %d bytes\n", parsed, expected)
			}
			os.Exit(1)
		}
	}

	start := time.Now()
	index := 0
	for ; index < iterations; index++ {
		parsed, err = session.Parse(data)
		if err != nil || parsed != expected {
			break
		}
	}
	elapsed := time.Since(start).Nanoseconds()
	if err != nil || parsed != expected {
		if err != nil {
			fmt.Fprintf(os.Stderr, "parse failed at iteration %d: %v\n", index, err)
		} else {
			fmt.Fprintf(os.Stderr, "parse failed at iteration %d: parsed %d of %d bytes\n", index, parsed, expected)
		}
		os.Exit(1)
	}
	total := uint64(expected) * uint64(iterations)
	var bps uint64
	if elapsed > 0 {
		bps = total * 1000000000 / uint64(elapsed)
	}

	fmt.Printf("input: %s\n", path)
	fmt.Printf("bytes: %s\n", withThousands(uint64(expected)))
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
