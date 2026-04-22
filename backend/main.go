package main

import (
	"log"

	"github.com/aadhii-yz/PocketLedger/backend/collections"
	"github.com/aadhii-yz/PocketLedger/backend/handlers"
	"github.com/aadhii-yz/PocketLedger/backend/middleware"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

func main() {
	app := pocketbase.New()

	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		if err := collections.CreateCollections(app); err != nil {
			return err
		}

		// All custom routes live under /api/custom and require auth.
		g := se.Router.Group("/api/custom")
		g.Bind(apis.RequireAuth())

		// Barcode
		g.GET("/barcode/{productId}", handlers.GetBarcode(app))
		g.POST("/barcode/generate", handlers.GenerateBarcode(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))

		// Billing — atomic: bill + bill_items + stock deduction in one tx
		g.POST("/bills/create", handlers.CreateBill(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "pos"))

		// Stock
		g.POST("/stock/adjust", handlers.AdjustStock(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))
		g.GET("/stock/alerts", handlers.StockAlerts(app)).
			BindFunc(middleware.RequireRole("admin", "manager"))

		// Stats
		g.GET("/stats/dashboard", handlers.Dashboard(app)).
			BindFunc(middleware.RequireRole("admin", "manager"))

		return se.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
