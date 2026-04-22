package services

import (
	"bytes"
	"fmt"
	"image/png"

	"github.com/boombuler/barcode"
	"github.com/boombuler/barcode/code128"
)

// GenerateBarcodePNG returns a Code128 barcode as a PNG byte slice.
// value is the barcode string (e.g. "INV0042" or a custom SKU).
func GenerateBarcodePNG(value string) ([]byte, error) {
	if value == "" {
		return nil, fmt.Errorf("barcode value cannot be empty")
	}

	// Encode as Code128
	bc, err := code128.Encode(value)
	if err != nil {
		return nil, fmt.Errorf("barcode encode failed: %w", err)
	}

	// Scale to a readable size: 300px wide × 80px tall
	scaled, err := barcode.Scale(bc, 300, 80)
	if err != nil {
		return nil, fmt.Errorf("barcode scale failed: %w", err)
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, scaled); err != nil {
		return nil, fmt.Errorf("barcode png encode failed: %w", err)
	}
	return buf.Bytes(), nil
}
