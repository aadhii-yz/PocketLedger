package handlers

import (
	"fmt"
	"net/http"
	"time"

	"github.com/aadhii-yz/PocketLedger/backend/services"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

type CartItem struct {
	ProductID string  `json:"product_id"`
	Quantity  float64 `json:"quantity"`
	UnitPrice float64 `json:"unit_price"`
	TaxRate   float64 `json:"tax_rate"`
}

type CreateBillRequest struct {
	CustomerName  string     `json:"customer_name"`
	CustomerPhone string     `json:"customer_phone"`
	Items         []CartItem `json:"items"`
	Discount      float64    `json:"discount"`
	PaymentMethod string     `json:"payment_method"`
	PaymentStatus string     `json:"payment_status"`
	Notes         string     `json:"notes"`
}

// CreateBill atomically creates a bill, bill_items, deducts stock and logs movements.
// Everything runs in a single SQLite transaction — if stock is insufficient the entire bill rolls back.
func CreateBill(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		var req CreateBillRequest
		if err := e.BindBody(&req); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}
		if len(req.Items) == 0 {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "cart is empty"})
		}

		var billId, billNumber string
		var grandTotal float64

		err := app.RunInTransaction(func(txApp core.App) error {
			num, err := services.NextBillNumber(txApp)
			if err != nil {
				return err
			}
			billNumber = num

			// Total
			var subtotal, taxTotal float64
			for _, item := range req.Items {
				line := item.Quantity * item.UnitPrice
				subtotal += line
				taxTotal += line * (item.TaxRate / 100)
			}
			grandTotal = subtotal + taxTotal - req.Discount
			if grandTotal < 0 {
				grandTotal = 0
			}

			// Bill record
			billsCol, err := txApp.FindCollectionByNameOrId("bills")
			if err != nil {
				return err
			}
			bill := core.NewRecord(billsCol)
			bill.Set("bill_number", billNumber)
			bill.Set("customer_name", req.CustomerName)
			bill.Set("customer_phone", req.CustomerPhone)
			bill.Set("items", req.Items)
			bill.Set("subtotal", subtotal)
			bill.Set("tax_total", taxTotal)
			bill.Set("discount", req.Discount)
			bill.Set("grand_total", grandTotal)
			bill.Set("payment_method", req.PaymentMethod)
			bill.Set("payment_status", req.PaymentStatus)
			bill.Set("created_by", e.Auth.Id)
			bill.Set("notes", req.Notes)
			if err := txApp.Save(bill); err != nil {
				return err
			}
			billId = bill.Id

			// Bill items + stock deduction
			billItemsCol, err := txApp.FindCollectionByNameOrId("bill_items")
			if err != nil {
				return err
			}
			movementsCol, err := txApp.FindCollectionByNameOrId("stock_movements")
			if err != nil {
				return err
			}

			for _, item := range req.Items {
				product, err := txApp.FindRecordById("products", item.ProductID)
				if err != nil {
					return fmt.Errorf("product %s not found: %w", item.ProductID, err)
				}

				// Bill item (price snapshot)
				bi := core.NewRecord(billItemsCol)
				bi.Set("bill", billId)
				bi.Set("product", product.Id)
				bi.Set("product_name", product.GetString("name"))
				bi.Set("quantity", item.Quantity)
				bi.Set("unit_price", item.UnitPrice)
				bi.Set("tax_rate", item.TaxRate)
				bi.Set("line_total", item.Quantity*item.UnitPrice)
				if err := txApp.Save(bi); err != nil {
					return err
				}

				// Find and deduct stock
				stockRecords, err := txApp.FindRecordsByFilter(
					"stock",
					"product = {:product}",
					"-created", 1, 0,
					dbx.Params{"product": product.Id},
				)
				if err != nil || len(stockRecords) == 0 {
					return fmt.Errorf("no stock record for %q — add stock first", product.GetString("name"))
				}
				sr := stockRecords[0]
				available := sr.GetFloat("quantity")
				if available < item.Quantity {
					return fmt.Errorf("insufficient stock for %q (available: %.2f, requested: %.2f)",
						product.GetString("name"), available, item.Quantity)
				}
				sr.Set("quantity", available-item.Quantity)
				if err := txApp.Save(sr); err != nil {
					return err
				}

				// Stock movement log
				mv := core.NewRecord(movementsCol)
				mv.Set("product", product.Id)
				mv.Set("type", "sale")
				mv.Set("quantity", -item.Quantity)
				mv.Set("reference", billNumber)
				mv.Set("note", fmt.Sprintf("Sale — %s @ %s", billNumber, time.Now().Format("2006-01-02 15:04")))
				if err := txApp.Save(mv); err != nil {
					return err
				}
			}
			return nil
		})

		if err != nil {
			return e.JSON(http.StatusUnprocessableEntity, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusCreated, map[string]any{
			"bill_id":     billId,
			"bill_number": billNumber,
			"grand_total": grandTotal,
		})
	}
}
