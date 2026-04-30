package handlers

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/aadhii-yz/PocketLedger/backend/services"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

type transferItemInput struct {
	ProductID string  `json:"product_id"`
	Quantity  float64 `json:"quantity"`
	Note      string  `json:"note"`
}

type createTransferRequest struct {
	FromLocation string              `json:"from_location"`
	ToLocation   string              `json:"to_location"`
	Notes        string              `json:"notes"`
	Items        []transferItemInput `json:"items"`
}

// ListTransfers returns transfers with optional ?status=, ?from_location=, ?to_location= filters.
func ListTransfers(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		q := e.Request.URL.Query()
		var parts []string
		params := dbx.Params{}

		if s := q.Get("status"); s != "" {
			parts = append(parts, "status = {:status}")
			params["status"] = s
		}
		if f := q.Get("from_location"); f != "" {
			parts = append(parts, "from_location = {:from}")
			params["from"] = f
		}
		if t := q.Get("to_location"); t != "" {
			parts = append(parts, "to_location = {:to}")
			params["to"] = t
		}

		filter := "id != ''"
		if len(parts) > 0 {
			filter = strings.Join(parts, " && ")
		}

		records, err := app.FindRecordsByFilter(
			"stock_transfers", filter, "-created", 0, 0, params,
		)
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}

		// Expand location names inline.
		result := make([]map[string]any, 0, len(records))
		for _, r := range records {
			fromName, toName := "", ""
			if fl, err := app.FindRecordById("locations", r.GetString("from_location")); err == nil {
				fromName = fl.GetString("name")
			}
			if tl, err := app.FindRecordById("locations", r.GetString("to_location")); err == nil {
				toName = tl.GetString("name")
			}
			result = append(result, map[string]any{
				"id":                 r.Id,
				"transfer_number":    r.GetString("transfer_number"),
				"from_location":      r.GetString("from_location"),
				"from_location_name": fromName,
				"to_location":        r.GetString("to_location"),
				"to_location_name":   toName,
				"status":             r.GetString("status"),
				"notes":              r.GetString("notes"),
				"created_by":         r.GetString("created_by"),
				"created":            r.GetString("created"),
			})
		}
		return e.JSON(http.StatusOK, result)
	}
}

// CreateTransfer creates a pending stock transfer with its line items.
func CreateTransfer(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		var req createTransferRequest
		if err := e.BindBody(&req); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}
		if req.FromLocation == "" || req.ToLocation == "" {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "from_location and to_location are required"})
		}
		if req.FromLocation == req.ToLocation {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "from_location and to_location must be different"})
		}
		if len(req.Items) == 0 {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "items cannot be empty"})
		}
		for _, item := range req.Items {
			if item.Quantity <= 0 {
				return e.JSON(http.StatusBadRequest, map[string]string{"message": "all item quantities must be positive"})
			}
		}

		var transferId, transferNumber string

		err := app.RunInTransaction(func(txApp core.App) error {
			// Validate stock availability before creating any records.
			for _, item := range req.Items {
				product, err := txApp.FindRecordById("products", item.ProductID)
				if err != nil {
					return fmt.Errorf("product %s not found", item.ProductID)
				}
				fromStock, err := txApp.FindRecordsByFilter(
					"stock",
					"product = {:product} && location = {:location}",
					"", 1, 0,
					dbx.Params{"product": item.ProductID, "location": req.FromLocation},
				)
				if err != nil || len(fromStock) == 0 {
					return fmt.Errorf("no stock record for %q at source location — add stock first", product.GetString("name"))
				}
				available := fromStock[0].GetFloat("quantity")
				if available < item.Quantity {
					return fmt.Errorf("insufficient stock for %q at source (available: %.2f, requested: %.2f)",
						product.GetString("name"), available, item.Quantity)
				}
			}

			num, err := services.NextTransferNumber(txApp)
			if err != nil {
				return err
			}
			transferNumber = num

			trCol, err := txApp.FindCollectionByNameOrId("stock_transfers")
			if err != nil {
				return err
			}
			tr := core.NewRecord(trCol)
			tr.Set("transfer_number", transferNumber)
			tr.Set("from_location", req.FromLocation)
			tr.Set("to_location", req.ToLocation)
			tr.Set("status", "pending")
			tr.Set("notes", req.Notes)
			tr.Set("created_by", e.Auth.Id)
			if err := txApp.Save(tr); err != nil {
				return err
			}
			transferId = tr.Id

			tiCol, err := txApp.FindCollectionByNameOrId("stock_transfer_items")
			if err != nil {
				return err
			}
			for _, item := range req.Items {
				product, err := txApp.FindRecordById("products", item.ProductID)
				if err != nil {
					return fmt.Errorf("product %s not found: %w", item.ProductID, err)
				}
				ti := core.NewRecord(tiCol)
				ti.Set("transfer", transferId)
				ti.Set("product", product.Id)
				ti.Set("product_name", product.GetString("name"))
				ti.Set("quantity", item.Quantity)
				ti.Set("note", item.Note)
				if err := txApp.Save(ti); err != nil {
					return err
				}
			}

			if logsCol, lerr := txApp.FindCollectionByNameOrId("system_logs"); lerr == nil {
				logRec := core.NewRecord(logsCol)
				logRec.Set("level", "INFO")
				logRec.Set("message", fmt.Sprintf("POST /api/custom/transfers/create — %s created", transferNumber))
				logRec.Set("status_code", 201)
				logRec.Set("details", fmt.Sprintf("From: %s → To: %s | Items: %d", req.FromLocation, req.ToLocation, len(req.Items)))
				logRec.Set("source", "stock")
				logRec.Set("user_id", e.Auth.Id)
				_ = txApp.Save(logRec)
			}
			return nil
		})

		if err != nil {
			return e.JSON(http.StatusUnprocessableEntity, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusCreated, map[string]any{
			"transfer_id":     transferId,
			"transfer_number": transferNumber,
		})
	}
}

// CompleteTransfer atomically deducts source stock, credits destination stock,
// logs movements, and sets status to completed.
func CompleteTransfer(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		id := e.Request.PathValue("id")

		err := app.RunInTransaction(func(txApp core.App) error {
			transfer, err := txApp.FindRecordById("stock_transfers", id)
			if err != nil {
				return fmt.Errorf("transfer not found: %w", err)
			}
			if transfer.GetString("status") != "pending" {
				return fmt.Errorf("only pending transfers can be completed (current status: %s)", transfer.GetString("status"))
			}

			fromLoc := transfer.GetString("from_location")
			toLoc := transfer.GetString("to_location")
			transferNumber := transfer.GetString("transfer_number")

			items, err := txApp.FindRecordsByFilter(
				"stock_transfer_items",
				"transfer = {:transfer}",
				"", 0, 0,
				dbx.Params{"transfer": id},
			)
			if err != nil {
				return fmt.Errorf("failed to load transfer items: %w", err)
			}
			if len(items) == 0 {
				return fmt.Errorf("transfer has no items")
			}

			stockCol, err := txApp.FindCollectionByNameOrId("stock")
			if err != nil {
				return err
			}
			movCol, err := txApp.FindCollectionByNameOrId("stock_movements")
			if err != nil {
				return err
			}

			for _, item := range items {
				productId := item.GetString("product")
				productName := item.GetString("product_name")
				qty := item.GetFloat("quantity")

				// Deduct from source location.
				fromStock, err := txApp.FindRecordsByFilter(
					"stock",
					"product = {:product} && location = {:location}",
					"", 1, 0,
					dbx.Params{"product": productId, "location": fromLoc},
				)
				if err != nil || len(fromStock) == 0 {
					return fmt.Errorf("no stock record for %q at source location — add stock first", productName)
				}
				fromSR := fromStock[0]
				available := fromSR.GetFloat("quantity")
				if available < qty {
					return fmt.Errorf("insufficient stock for %q at source (available: %.2f, requested: %.2f)",
						productName, available, qty)
				}
				fromSR.Set("quantity", available-qty)
				if err := txApp.Save(fromSR); err != nil {
					return err
				}

				// Credit destination location (find or create).
				toStockRecords, err := txApp.FindRecordsByFilter(
					"stock",
					"product = {:product} && location = {:location}",
					"", 1, 0,
					dbx.Params{"product": productId, "location": toLoc},
				)
				if err != nil {
					return err
				}
				var toSR *core.Record
				if len(toStockRecords) > 0 {
					toSR = toStockRecords[0]
					toSR.Set("quantity", toSR.GetFloat("quantity")+qty)
				} else {
					toSR = core.NewRecord(stockCol)
					toSR.Set("product", productId)
					toSR.Set("location", toLoc)
					toSR.Set("quantity", qty)
				}
				if err := txApp.Save(toSR); err != nil {
					return err
				}

				// Movement: transfer_out from source.
				mvOut := core.NewRecord(movCol)
				mvOut.Set("product", productId)
				mvOut.Set("location", fromLoc)
				mvOut.Set("type", "transfer_out")
				mvOut.Set("quantity", -qty)
				mvOut.Set("reference", transferNumber)
				mvOut.Set("note", fmt.Sprintf("Transfer out — %s", transferNumber))
				if err := txApp.Save(mvOut); err != nil {
					return err
				}

				// Movement: transfer_in to destination.
				mvIn := core.NewRecord(movCol)
				mvIn.Set("product", productId)
				mvIn.Set("location", toLoc)
				mvIn.Set("type", "transfer_in")
				mvIn.Set("quantity", qty)
				mvIn.Set("reference", transferNumber)
				mvIn.Set("note", fmt.Sprintf("Transfer in — %s", transferNumber))
				if err := txApp.Save(mvIn); err != nil {
					return err
				}
			}

			// Mark transfer as completed.
			transfer.Set("status", "completed")
			if err := txApp.Save(transfer); err != nil {
				return err
			}

			if logsCol, lerr := txApp.FindCollectionByNameOrId("system_logs"); lerr == nil {
				logRec := core.NewRecord(logsCol)
				logRec.Set("level", "INFO")
				logRec.Set("message", fmt.Sprintf("POST /api/custom/transfers/%s/complete — %s completed", id, transferNumber))
				logRec.Set("status_code", 200)
				logRec.Set("details", fmt.Sprintf("From: %s → To: %s | Items: %d", fromLoc, toLoc, len(items)))
				logRec.Set("source", "stock")
				logRec.Set("user_id", e.Auth.Id)
				_ = txApp.Save(logRec)
			}
			return nil
		})

		if err != nil {
			return e.JSON(http.StatusUnprocessableEntity, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, map[string]string{"status": "completed"})
	}
}

// CancelTransfer sets a pending transfer to cancelled. No stock changes.
func CancelTransfer(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		id := e.Request.PathValue("id")

		err := app.RunInTransaction(func(txApp core.App) error {
			transfer, err := txApp.FindRecordById("stock_transfers", id)
			if err != nil {
				return fmt.Errorf("transfer not found: %w", err)
			}
			if transfer.GetString("status") != "pending" {
				return fmt.Errorf("only pending transfers can be cancelled (current status: %s)", transfer.GetString("status"))
			}

			transfer.Set("status", "cancelled")
			if err := txApp.Save(transfer); err != nil {
				return err
			}

			if logsCol, lerr := txApp.FindCollectionByNameOrId("system_logs"); lerr == nil {
				logRec := core.NewRecord(logsCol)
				logRec.Set("level", "INFO")
				logRec.Set("message", fmt.Sprintf("POST /api/custom/transfers/%s/cancel — %s cancelled", id, transfer.GetString("transfer_number")))
				logRec.Set("status_code", 200)
				logRec.Set("source", "stock")
				logRec.Set("user_id", e.Auth.Id)
				_ = txApp.Save(logRec)
			}
			return nil
		})

		if err != nil {
			return e.JSON(http.StatusUnprocessableEntity, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, map[string]string{"status": "cancelled"})
	}
}
