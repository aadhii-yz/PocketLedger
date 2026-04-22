package handlers

import (
	"fmt"
	"net/http"

	"github.com/pocketbase/pocketbase/core"
)

func GetBarcode(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		return nil
	}
}
func GenerateBarcode(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		var body struct {
			ProductID string `json:"product_id"`
			Value     string `json:"value"`
		}
		if err := e.BindBody(&body); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}
		product, err := app.FindRecordById("products", body.ProductID)
		if err != nil {
			return e.JSON(http.StatusNotFound, map[string]string{"message": "product not found"})
		}
		barcodeValue := body.Value
		if barcodeValue == "" {
			barcodeValue = fmt.Sprintf("INV%s", product.GetString("sku"))
		}
		product.Set("barcode", barcodeValue)
		if err := app.Save(product); err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, map[string]any{
			"barcode": barcodeValue,
			"product": product.Id,
			"png_url": fmt.Sprintf("/api/custom/barcode/%s", product.Id),
		})
	}
}
