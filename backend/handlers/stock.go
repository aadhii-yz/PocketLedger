package handlers

import (
	"fmt"
	"net/http"

	"github.com/aadhii-yz/PocketLedger/backend/services"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

type StockAdjustRequest struct {
	ProductID  string  `json:"product_id"`
	LocationID string  `json:"location_id"`
	Quantity   float64 `json:"quantity"` // positive = add, negative = remove
	Type       string  `json:"type"`     // purchase | adjustment | return
	Note       string  `json:"note"`
}

// AdjustStock manually adjusts a product's stock at a specific location and logs the movement.
func AdjustStock(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		var req StockAdjustRequest
		if err := e.BindBody(&req); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}
		if req.LocationID == "" {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "location_id is required"})
		}

		err := app.RunInTransaction(func(txApp core.App) error {
			stockRecords, err := txApp.FindRecordsByFilter(
				"stock",
				"product = {:product} && location = {:location}",
				"-created", 1, 0,
				dbx.Params{"product": req.ProductID, "location": req.LocationID},
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
				sr.Set("location", req.LocationID)
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
			mv.Set("location", req.LocationID)
			mv.Set("type", req.Type)
			mv.Set("quantity", req.Quantity)
			mv.Set("note", req.Note)
			if err := txApp.Save(mv); err != nil {
				return err
			}

			if logsCol, lerr := txApp.FindCollectionByNameOrId("system_logs"); lerr == nil {
				logRec := core.NewRecord(logsCol)
				logRec.Set("level", "INFO")
				logRec.Set("message", fmt.Sprintf("POST /api/custom/stock/adjust — %s | product: %s", req.Type, req.ProductID))
				logRec.Set("status_code", 200)
				logRec.Set("details", fmt.Sprintf("Location: %s | Quantity: %.2f | Note: %s", req.LocationID, req.Quantity, req.Note))
				logRec.Set("source", "stock")
				logRec.Set("user_id", e.Auth.Id)
				_ = txApp.Save(logRec)
			}

			return nil
		})

		if err != nil {
			return e.JSON(http.StatusUnprocessableEntity, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, map[string]string{"status": "ok"})
	}
}

// StockAlerts returns products at or below their low_stock_threshold.
// Optional ?location_id= query param scopes results to a single location.
func StockAlerts(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		locationId := e.Request.URL.Query().Get("location_id")
		items, err := services.GetLowStock(app, locationId)
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, items)
	}
}
