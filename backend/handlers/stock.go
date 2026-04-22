package handlers

import (
	"fmt"
	"net/http"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

type StockAdjustRequest struct {
	ProductID string  `json:"product_id"`
	Quantity  float64 `json:"quantity"` // positive = add, negative = remove
	Type      string  `json:"type"`     // purchase | adjustment | return
	Note      string  `json:"note"`
}

// AdjustStock manually adjusts a product's stock and logs the movement.
func AdjustStock(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		var req StockAdjustRequest
		if err := e.BindBody(&req); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}

		err := app.RunInTransaction(func(txApp core.App) error {
			stockRecords, err := txApp.FindRecordsByFilter(
				"stock", "product = {:product}", "-created", 1, 0,
				dbx.Params{"product": req.ProductID},
			)

			if err != nil || len(stockRecords) == 0 {
				if req.Quantity < 0 {
					return fmt.Errorf("cannot set negative stock for a new product")
				}
				stockCol, err := txApp.FindCollectionByNameOrId("stock")
				if err != nil {
					return err
				}
				sr := core.NewRecord(stockCol)
				sr.Set("product", req.ProductID)
				sr.Set("quantity", req.Quantity)
				if err := txApp.Save(sr); err != nil {
					return err
				}
			} else {
				sr := stockRecords[0]
				newQty := sr.GetFloat("quantity") + req.Quantity
				if newQty < 0 {
					return fmt.Errorf("adjustment would result in negative stock (current: %.2f, delta: %.2f)",
						sr.GetFloat("quantity"), req.Quantity)
				}
				sr.Set("quantity", newQty)
				if err := txApp.Save(sr); err != nil {
					return err
				}
			}

			movCol, err := txApp.FindCollectionByNameOrId("stock_movements")
			if err != nil {
				return err
			}
			mv := core.NewRecord(movCol)
			mv.Set("product", req.ProductID)
			mv.Set("type", req.Type)
			mv.Set("quantity", req.Quantity)
			mv.Set("note", req.Note)
			return txApp.Save(mv)
		})

		if err != nil {
			return e.JSON(http.StatusUnprocessableEntity, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, map[string]string{"status": "ok"})
	}
}

// StockAlerts returns products at or below their low_stock_threshold.
func StockAlerts(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		return nil
	}
}
