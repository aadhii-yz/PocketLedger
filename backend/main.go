package main

import (
	"log"
	"os"

	"github.com/aadhii-yz/PocketLedger/backend/collections"
	"github.com/aadhii-yz/PocketLedger/backend/handlers"
	"github.com/aadhii-yz/PocketLedger/backend/middleware"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

func main() {
	app := pocketbase.New()

	// Prevent deleting products that still have stock records.
	app.OnRecordDelete("products").BindFunc(func(e *core.RecordEvent) error {
		var count int
		if err := app.DB().NewQuery("SELECT COUNT(*) FROM stock WHERE product = {:id}").
			Bind(dbx.Params{"id": e.Record.Id}).Row(&count); err == nil && count > 0 {
			return apis.NewBadRequestError("Cannot delete a product that has stock records. Remove all stock entries first.", nil)
		}
		return e.Next()
	})

	// Prevent deleting locations that are still referenced by stock, bills, or transfers.
	app.OnRecordDelete("locations").BindFunc(func(e *core.RecordEvent) error {
		id := e.Record.Id
		var stockCount, billCount, transferCount int
		app.DB().NewQuery("SELECT COUNT(*) FROM stock WHERE location = {:id}").Bind(dbx.Params{"id": id}).Row(&stockCount)
		app.DB().NewQuery("SELECT COUNT(*) FROM bills WHERE shop = {:id}").Bind(dbx.Params{"id": id}).Row(&billCount)
		app.DB().NewQuery("SELECT COUNT(*) FROM stock_transfers WHERE from_location = {:id} OR to_location = {:id}").Bind(dbx.Params{"id": id}).Row(&transferCount)
		if stockCount+billCount+transferCount > 0 {
			return apis.NewBadRequestError("Cannot delete a location that has associated stock, bills, or transfers.", nil)
		}
		return e.Next()
	})

	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		if err := collections.CreateCollections(app); err != nil {
			return err
		}

		// Prune system_logs older than 90 days.
		app.DB().NewQuery("DELETE FROM system_logs WHERE created < datetime('now', '-90 days')").Execute()

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

		// Locations
		g.GET("/locations", handlers.ListLocations(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "pos", "stock_entry"))
		g.POST("/locations", handlers.CreateLocation(app)).
			BindFunc(middleware.RequireRole("admin", "manager"))
		g.PATCH("/locations/{id}", handlers.UpdateLocation(app)).
			BindFunc(middleware.RequireRole("admin", "manager"))

		// Stock
		g.POST("/stock/adjust", handlers.AdjustStock(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))
		g.GET("/stock/alerts", handlers.StockAlerts(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))

		// Transfers
		g.GET("/transfers", handlers.ListTransfers(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))
		g.POST("/transfers/create", handlers.CreateTransfer(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))
		g.POST("/transfers/{id}/complete", handlers.CompleteTransfer(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))
		g.POST("/transfers/{id}/cancel", handlers.CancelTransfer(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "stock_entry"))

		// Stats
		g.GET("/stats/dashboard", handlers.Dashboard(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "pos", "stock_entry"))

		// System Logs
		g.POST("/logs", handlers.CreateLog(app)).
			BindFunc(middleware.RequireRole("admin", "manager", "pos", "stock_entry"))
		g.GET("/logs", handlers.GetLogs(app)).
			BindFunc(middleware.RequireRole("admin"))

		// Frontend as Static site
		se.Router.GET("/{path...}", apis.Static(os.DirFS("./pb_public"), true))

		return se.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
