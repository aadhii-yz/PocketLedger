package handlers

import "github.com/pocketbase/pocketbase/core"

// AdjustStock manually adjusts a product's stock and logs the movement.
func AdjustStock(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		return nil
	}
}

// StockAlerts returns products at or below their low_stock_threshold.
func StockAlerts(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		return nil
	}
}
