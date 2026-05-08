package collections

import (
	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

func CreateCollections(app core.App) error {
	for _, fn := range []func(core.App) error{
		ensureLocations,
		ensureUsersExtended,
		ensureCategories,
		ensureProducts,
		ensureStock,
		ensureStockMovements,
		ensureBills,
		ensureBillItems,
		ensureSystemLogs,
		ensureStockTransfers,
		ensureStockTransferItems,
		ensurePrintSettings,
	} {
		if err := fn(app); err != nil {
			return err
		}
	}
	return EnsureDefaultLocations(app)
}

// Helper function
func colId(app core.App, name string) string {
	col, err := app.FindCollectionByNameOrId(name)
	if err != nil || col == nil {
		return ""
	}
	return col.Id
}

func ensureLocations(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("locations"); err == nil {
		return nil
	}
	col := core.NewBaseCollection("locations")
	col.ListRule = new("@request.auth.id != ''")
	col.ViewRule = new("@request.auth.id != ''")
	col.CreateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")
	col.UpdateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.TextField{Name: "name", Required: true})
	col.Fields.Add(&core.SelectField{
		Name:      "type",
		MaxSelect: 1,
		Values:    []string{"warehouse", "shop"},
	})
	col.Fields.Add(&core.TextField{Name: "address"})
	col.Fields.Add(&core.TextField{Name: "phone"})
	col.Fields.Add(&core.BoolField{Name: "is_active"})
	return app.Save(col)
}

func ensureUsersExtended(app core.App) error {
	col, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		return err
	}

	apiRule := "@request.auth.role = 'admin' || @request.auth.role = 'manager'"
	col.ListRule = &apiRule
	col.ViewRule = &apiRule
	col.CreateRule = &apiRule
	col.UpdateRule = &apiRule
	col.DeleteRule = &apiRule

	changed := false

	if col.Fields.GetByName("role") == nil {
		col.Fields.Add(&core.SelectField{
			Name:      "role",
			Required:  true,
			MaxSelect: 1,
			Values:    []string{"admin", "manager", "pos", "stock_entry"},
		})
		changed = true
	}

	if col.Fields.GetByName("assigned_shop") == nil {
		col.Fields.Add(&core.RelationField{
			Name:         "assigned_shop",
			CollectionId: colId(app, "locations"),
			MaxSelect:    1,
		})
		changed = true
	}

	if !changed {
		return nil
	}
	return app.Save(col)
}

func ensureCategories(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("categories"); err == nil {
		return nil
	}
	col := core.NewBaseCollection("categories")
	col.ListRule = new("@request.auth.id != ''")
	col.ViewRule = new("@request.auth.id != ''")
	col.CreateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'")
	col.UpdateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.TextField{Name: "name", Required: true})
	col.Fields.Add(&core.TextField{Name: "description"})
	return app.Save(col)
}

func ensureProducts(app core.App) error {
	editRole := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'"
	col, err := app.FindCollectionByNameOrId("products")
	if err != nil {
		// Fresh install.
		col = core.NewBaseCollection("products")
		col.ListRule = new("@request.auth.id != ''")
		col.ViewRule = new("@request.auth.id != ''")
		col.CreateRule = new(editRole)
		col.UpdateRule = new(editRole)
		col.DeleteRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")
		col.Fields.Add(&core.TextField{Name: "name", Required: true})
		col.Fields.Add(&core.TextField{Name: "sku", Required: true})
		col.Fields.Add(&core.TextField{Name: "barcode"})
		col.Fields.Add(&core.RelationField{
			Name:         "category",
			CollectionId: colId(app, "categories"),
			MaxSelect:    1,
		})
		col.Fields.Add(&core.SelectField{
			Name:      "unit",
			MaxSelect: 1,
			Values:    []string{"piece", "kg", "litre", "box"},
		})
		col.Fields.Add(&core.NumberField{Name: "cost_price", Required: true})
		col.Fields.Add(&core.NumberField{Name: "selling_price", Required: true})
		col.Fields.Add(&core.NumberField{Name: "tax_rate"})
		col.Fields.Add(&core.FileField{Name: "image", MaxSelect: 1, MaxSize: 5242880})
		col.Indexes = append(col.Indexes,
			"CREATE UNIQUE INDEX idx_products_sku ON {{products}} (sku)",
			"CREATE UNIQUE INDEX idx_products_barcode ON {{products}} (barcode) WHERE barcode != ''",
		)
		return app.Save(col)
	}

	// Upgrade path — add unique indexes if missing.
	changed := false
	hasSKUIdx, hasBarcodeIdx := false, false
	for _, idx := range col.Indexes {
		if strings.Contains(idx, "idx_products_sku") {
			hasSKUIdx = true
		}
		if strings.Contains(idx, "idx_products_barcode") {
			hasBarcodeIdx = true
		}
	}
	if !hasSKUIdx {
		col.Indexes = append(col.Indexes, "CREATE UNIQUE INDEX idx_products_sku ON {{products}} (sku)")
		changed = true
	}
	if !hasBarcodeIdx {
		col.Indexes = append(col.Indexes, "CREATE UNIQUE INDEX idx_products_barcode ON {{products}} (barcode) WHERE barcode != ''")
		changed = true
	}
	if !changed {
		return nil
	}
	return app.Save(col)
}

func ensureStock(app core.App) error {
	stockCol, err := app.FindCollectionByNameOrId("stock")
	if err != nil {
		editRole := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'"
		col := core.NewBaseCollection("stock")
		col.ListRule = new("@request.auth.id != ''")
		col.ViewRule = new("@request.auth.id != ''")
		col.CreateRule = new(editRole)
		col.UpdateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")
		col.DeleteRule = new("@request.auth.role = 'admin'")
		col.Fields.Add(&core.RelationField{
			Name:         "product",
			Required:     true,
			CollectionId: colId(app, "products"),
			MaxSelect:    1,
		})
		col.Fields.Add(&core.RelationField{
			Name:         "location",
			Required:     true,
			CollectionId: colId(app, "locations"),
			MaxSelect:    1,
		})
		col.Fields.Add(&core.NumberField{Name: "quantity", Required: true})
		col.Fields.Add(&core.NumberField{Name: "low_stock_threshold"})
		col.Indexes = append(col.Indexes,
			"CREATE INDEX IF NOT EXISTS idx_stock_product_location ON {{stock}} (product, location)",
		)
		return app.Save(col)
	}

	// Upgrade path — add location if missing (Required: false to avoid breaking existing rows).
	changed := false
	if stockCol.Fields.GetByName("location") == nil {
		stockCol.Fields.Add(&core.RelationField{
			Name:         "location",
			CollectionId: colId(app, "locations"),
			MaxSelect:    1,
		})
		changed = true
	}
	newStockUpdateRule := "@request.auth.role = 'admin' || @request.auth.role = 'manager'"
	if stockCol.UpdateRule == nil || *stockCol.UpdateRule != newStockUpdateRule {
		stockCol.UpdateRule = &newStockUpdateRule
		changed = true
	}
	hasStockIdx := false
	for _, idx := range stockCol.Indexes {
		if strings.Contains(idx, "idx_stock_product_location") {
			hasStockIdx = true
		}
	}
	if !hasStockIdx {
		stockCol.Indexes = append(stockCol.Indexes, "CREATE INDEX IF NOT EXISTS idx_stock_product_location ON {{stock}} (product, location)")
		changed = true
	}
	if !changed {
		return nil
	}
	return app.Save(stockCol)
}

func ensureStockMovements(app core.App) error {
	movCol, err := app.FindCollectionByNameOrId("stock_movements")
	if err != nil {
		// Fresh install.
		viewRole := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'"
		col := core.NewBaseCollection("stock_movements")
		col.ListRule = new(viewRole)
		col.ViewRule = new(viewRole)
		col.CreateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'")
		col.UpdateRule = new("@request.auth.role = 'admin'")
		col.DeleteRule = new("@request.auth.role = 'admin'")
		col.Fields.Add(&core.RelationField{
			Name:         "product",
			Required:     true,
			CollectionId: colId(app, "products"),
			MaxSelect:    1,
		})
		col.Fields.Add(&core.RelationField{
			Name:         "location",
			CollectionId: colId(app, "locations"),
			MaxSelect:    1,
		})
		col.Fields.Add(&core.SelectField{
			Name:      "type",
			Required:  true,
			MaxSelect: 1,
			Values:    []string{"purchase", "sale", "adjustment", "return", "transfer_in", "transfer_out"},
		})
		col.Fields.Add(&core.NumberField{Name: "quantity", Required: true})
		col.Fields.Add(&core.TextField{Name: "reference"})
		col.Fields.Add(&core.TextField{Name: "note"})
		col.Indexes = append(col.Indexes,
			"CREATE INDEX IF NOT EXISTS idx_movements_product_location ON {{stock_movements}} (product, location DESC)",
		)
		return app.Save(col)
	}

	// Upgrade path.
	changed := false

	if movCol.Fields.GetByName("location") == nil {
		movCol.Fields.Add(&core.RelationField{
			Name:         "location",
			CollectionId: colId(app, "locations"),
			MaxSelect:    1,
		})
		changed = true
	}

	if typeField := movCol.Fields.GetByName("type"); typeField != nil {
		if sf, ok := typeField.(*core.SelectField); ok {
			existing := make(map[string]bool, len(sf.Values))
			for _, v := range sf.Values {
				existing[v] = true
			}
			for _, v := range []string{"transfer_in", "transfer_out"} {
				if !existing[v] {
					sf.Values = append(sf.Values, v)
					changed = true
				}
			}
		}
	}

	newMovCreateRule := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'"
	if movCol.CreateRule == nil || *movCol.CreateRule != newMovCreateRule {
		movCol.CreateRule = &newMovCreateRule
		changed = true
	}
	hasMovIdx := false
	for _, idx := range movCol.Indexes {
		if strings.Contains(idx, "idx_movements_product_location") {
			hasMovIdx = true
		}
	}
	if !hasMovIdx {
		movCol.Indexes = append(movCol.Indexes, "CREATE INDEX IF NOT EXISTS idx_movements_product_location ON {{stock_movements}} (product, location DESC)")
		changed = true
	}
	if !changed {
		return nil
	}
	return app.Save(movCol)
}

func ensureBills(app core.App) error {
	billsCol, err := app.FindCollectionByNameOrId("bills")
	if err != nil {
		// Fresh install.
		viewRule := "@request.auth.id != '' && (@request.auth.role = 'admin' || @request.auth.role = 'manager' || created_by = @request.auth.id)"
		col := core.NewBaseCollection("bills")
		col.ListRule = new(viewRule)
		col.ViewRule = new(viewRule)
		col.CreateRule = new("@request.auth.id != '' && (@request.auth.role != 'pos' || shop = @request.auth.assigned_shop)")
		col.UpdateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")
		col.DeleteRule = new("@request.auth.role = 'admin'")
		col.Fields.Add(&core.AutodateField{Name: "created", OnCreate: true})
		col.Fields.Add(&core.TextField{Name: "bill_number", Required: true})
		col.Fields.Add(&core.RelationField{
			Name:         "shop",
			CollectionId: colId(app, "locations"),
			MaxSelect:    1,
		})
		col.Fields.Add(&core.TextField{Name: "customer_name"})
		col.Fields.Add(&core.TextField{Name: "customer_phone"})
		col.Fields.Add(&core.JSONField{Name: "items"})
		col.Fields.Add(&core.NumberField{Name: "subtotal", Required: true})
		col.Fields.Add(&core.NumberField{Name: "tax_total"})
		col.Fields.Add(&core.NumberField{Name: "discount"})
		col.Fields.Add(&core.NumberField{Name: "grand_total", Required: true})
		col.Fields.Add(&core.SelectField{
			Name:      "payment_method",
			MaxSelect: 1,
			Values:    []string{"cash", "card", "upi", "credit"},
		})
		col.Fields.Add(&core.SelectField{
			Name:      "payment_status",
			MaxSelect: 1,
			Values:    []string{"paid", "pending", "partial"},
		})
		col.Fields.Add(&core.RelationField{
			Name:         "created_by",
			CollectionId: colId(app, "users"),
			MaxSelect:    1,
		})
		col.Fields.Add(&core.TextField{Name: "notes"})
		col.Indexes = append(col.Indexes,
			"CREATE INDEX IF NOT EXISTS idx_bills_shop_created ON {{bills}} (shop, created DESC)",
		)
		return app.Save(col)
	}

	// Upgrade path.
	changed := false

	if billsCol.Fields.GetByName("created") == nil {
		billsCol.Fields.Add(&core.AutodateField{Name: "created", OnCreate: true})
		changed = true
	}

	if billsCol.Fields.GetByName("shop") == nil {
		billsCol.Fields.Add(&core.RelationField{
			Name:         "shop",
			CollectionId: colId(app, "locations"),
			MaxSelect:    1,
		})
		changed = true
	}

	if pmField := billsCol.Fields.GetByName("payment_method"); pmField != nil {
		if sf, ok := pmField.(*core.SelectField); ok {
			existing := make(map[string]bool, len(sf.Values))
			for _, v := range sf.Values {
				existing[v] = true
			}
			if !existing["credit"] {
				sf.Values = append(sf.Values, "credit")
				changed = true
			}
		}
	}

	newBillsCreateRule := "@request.auth.id != '' && (@request.auth.role != 'pos' || shop = @request.auth.assigned_shop)"
	if billsCol.CreateRule == nil || *billsCol.CreateRule != newBillsCreateRule {
		billsCol.CreateRule = &newBillsCreateRule
		changed = true
	}
	hasBillsIdx := false
	for _, idx := range billsCol.Indexes {
		if strings.Contains(idx, "idx_bills_shop_created") {
			hasBillsIdx = true
		}
	}
	if !hasBillsIdx {
		billsCol.Indexes = append(billsCol.Indexes, "CREATE INDEX IF NOT EXISTS idx_bills_shop_created ON {{bills}} (shop, created DESC)")
		changed = true
	}
	if !changed {
		return nil
	}
	return app.Save(billsCol)
}

func ensureBillItems(app core.App) error {
	col, err := app.FindCollectionByNameOrId("bill_items")
	if err == nil {
		// Upgrade path: tighten createRule.
		newRule := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'pos'"
		if col.CreateRule == nil || *col.CreateRule != newRule {
			col.CreateRule = &newRule
			return app.Save(col)
		}
		return nil
	}
	// Fresh install.
	col = core.NewBaseCollection("bill_items")
	col.ListRule = new("@request.auth.id != ''")
	col.ViewRule = new("@request.auth.id != ''")
	col.CreateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'pos'")
	col.UpdateRule = new("@request.auth.role = 'admin'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.RelationField{
		Name:         "bill",
		Required:     true,
		CollectionId: colId(app, "bills"),
		MaxSelect:    1,
	})
	col.Fields.Add(&core.RelationField{
		Name:         "product",
		CollectionId: colId(app, "products"),
		MaxSelect:    1,
	})
	col.Fields.Add(&core.TextField{Name: "product_name", Required: true})
	col.Fields.Add(&core.NumberField{Name: "quantity", Required: true})
	col.Fields.Add(&core.NumberField{Name: "unit_price", Required: true})
	col.Fields.Add(&core.NumberField{Name: "tax_rate"})
	col.Fields.Add(&core.NumberField{Name: "line_total", Required: true})
	return app.Save(col)
}

func ensureSystemLogs(app core.App) error {
	col, err := app.FindCollectionByNameOrId("system_logs")
	if err == nil {
		// Upgrade path: add index if missing.
		for _, idx := range col.Indexes {
			if strings.Contains(idx, "idx_logs_created") {
				return nil
			}
		}
		col.Indexes = append(col.Indexes, "CREATE INDEX IF NOT EXISTS idx_logs_created ON {{system_logs}} (created DESC)")
		return app.Save(col)
	}
	// Fresh install.
	col = core.NewBaseCollection("system_logs")
	col.ListRule = new("@request.auth.role = 'admin'")
	col.ViewRule = new("@request.auth.role = 'admin'")
	col.CreateRule = new("@request.auth.id != ''")
	col.UpdateRule = nil
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.AutodateField{Name: "created", OnCreate: true})
	col.Fields.Add(&core.SelectField{
		Name:      "level",
		Required:  true,
		MaxSelect: 1,
		Values:    []string{"INFO", "WARNING", "ERROR"},
	})
	col.Fields.Add(&core.TextField{Name: "message", Required: true})
	col.Fields.Add(&core.NumberField{Name: "status_code"})
	col.Fields.Add(&core.TextField{Name: "details"})
	col.Fields.Add(&core.SelectField{
		Name:      "source",
		MaxSelect: 1,
		Values:    []string{"billing", "stock", "auth", "system"},
	})
	col.Fields.Add(&core.TextField{Name: "user_id"})
	col.Indexes = append(col.Indexes, "CREATE INDEX IF NOT EXISTS idx_logs_created ON {{system_logs}} (created DESC)")
	return app.Save(col)
}

func ensureStockTransfers(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("stock_transfers"); err == nil {
		return nil
	}
	adminManager := "@request.auth.role = 'admin' || @request.auth.role = 'manager'"
	col := core.NewBaseCollection("stock_transfers")
	col.ListRule = new(adminManager)
	col.ViewRule = new(adminManager)
	col.CreateRule = new(adminManager)
	col.UpdateRule = new("@request.auth.role = 'admin'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.TextField{Name: "transfer_number", Required: true})
	col.Fields.Add(&core.AutodateField{
		Name:     "created",
		OnCreate: true,
	})
	col.Fields.Add(&core.RelationField{
		Name:         "from_location",
		Required:     true,
		CollectionId: colId(app, "locations"),
		MaxSelect:    1,
	})
	col.Fields.Add(&core.RelationField{
		Name:         "to_location",
		Required:     true,
		CollectionId: colId(app, "locations"),
		MaxSelect:    1,
	})
	col.Fields.Add(&core.SelectField{
		Name:      "status",
		Required:  true,
		MaxSelect: 1,
		Values:    []string{"pending", "completed", "cancelled"},
	})
	col.Fields.Add(&core.TextField{Name: "notes"})
	col.Fields.Add(&core.RelationField{
		Name:         "created_by",
		CollectionId: colId(app, "users"),
		MaxSelect:    1,
	})
	return app.Save(col)
}

func ensureStockTransferItems(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("stock_transfer_items"); err == nil {
		return nil
	}
	adminManager := "@request.auth.role = 'admin' || @request.auth.role = 'manager'"
	col := core.NewBaseCollection("stock_transfer_items")
	col.ListRule = new(adminManager)
	col.ViewRule = new(adminManager)
	col.CreateRule = new(adminManager)
	col.UpdateRule = new("@request.auth.role = 'admin'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.RelationField{
		Name:         "transfer",
		Required:     true,
		CollectionId: colId(app, "stock_transfers"),
		MaxSelect:    1,
	})
	col.Fields.Add(&core.RelationField{
		Name:         "product",
		CollectionId: colId(app, "products"),
		MaxSelect:    1,
	})
	col.Fields.Add(&core.TextField{Name: "product_name", Required: true})
	col.Fields.Add(&core.NumberField{Name: "quantity", Required: true})
	col.Fields.Add(&core.TextField{Name: "note"})
	return app.Save(col)
}

func ensurePrintSettings(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("print_settings"); err == nil {
		return nil
	}
	authOnly := "@request.auth.id != ''"
	adminManager := "@request.auth.role = 'admin' || @request.auth.role = 'manager'"
	col := core.NewBaseCollection("print_settings")
	col.ListRule = &authOnly
	col.ViewRule = &authOnly
	col.CreateRule = &adminManager
	col.UpdateRule = &adminManager
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.TextField{Name: "shop_name"})
	col.Fields.Add(&core.TextField{Name: "shop_address"})
	col.Fields.Add(&core.TextField{Name: "shop_phone"})
	col.Fields.Add(&core.TextField{Name: "gst_number"})
	col.Fields.Add(&core.TextField{Name: "receipt_footer"})
	col.Fields.Add(&core.BoolField{Name: "show_customer_info"})
	col.Fields.Add(&core.BoolField{Name: "show_tax_breakdown"})
	col.Fields.Add(&core.BoolField{Name: "barcode_show_sku"})
	col.Fields.Add(&core.BoolField{Name: "barcode_show_price"})
	return app.Save(col)
}

func EnsureDefaultLocations(app core.App) error {
	// Step 1: find or create Central Warehouse.
	warehouseRecords, err := app.FindRecordsByFilter(
		"locations", "type = 'warehouse' && name = 'Central Warehouse'", "", 1, 0,
	)
	if err != nil {
		return err
	}
	var warehouseId string
	if len(warehouseRecords) > 0 {
		warehouseId = warehouseRecords[0].Id
	} else {
		locCol, err := app.FindCollectionByNameOrId("locations")
		if err != nil {
			return err
		}
		wh := core.NewRecord(locCol)
		wh.Set("name", "Central Warehouse")
		wh.Set("type", "warehouse")
		wh.Set("is_active", true)
		if err := app.Save(wh); err != nil {
			return err
		}
		warehouseId = wh.Id
	}

	// Step 2: find or create Main Shop.
	shopRecords, err := app.FindRecordsByFilter(
		"locations", "type = 'shop' && name = 'Main Shop'", "", 1, 0,
	)
	if err != nil {
		return err
	}
	var shopId string
	if len(shopRecords) > 0 {
		shopId = shopRecords[0].Id
	} else {
		locCol, err := app.FindCollectionByNameOrId("locations")
		if err != nil {
			return err
		}
		sh := core.NewRecord(locCol)
		sh.Set("name", "Main Shop")
		sh.Set("type", "shop")
		sh.Set("is_active", true)
		if err := app.Save(sh); err != nil {
			return err
		}
		shopId = sh.Id
	}

	db := app.DB()

	// Step 3: back-fill stock.location.
	if _, err := db.NewQuery(
		"UPDATE stock SET location = {:loc} WHERE location = '' OR location IS NULL",
	).Bind(dbx.Params{"loc": warehouseId}).Execute(); err != nil {
		return err
	}

	// Step 4: back-fill bills.shop.
	if _, err := db.NewQuery(
		"UPDATE bills SET shop = {:shop} WHERE shop = '' OR shop IS NULL",
	).Bind(dbx.Params{"shop": shopId}).Execute(); err != nil {
		return err
	}

	// Step 4b: back-fill bills.created for rows that have no timestamp.
	if _, err := db.NewQuery(
		"UPDATE bills SET created = datetime('now') WHERE created IS NULL OR created = ''",
	).Execute(); err != nil {
		return err
	}

	// Step 5: back-fill stock_movements.location.
	if _, err := db.NewQuery(
		"UPDATE stock_movements SET location = {:loc} WHERE location = '' OR location IS NULL",
	).Bind(dbx.Params{"loc": warehouseId}).Execute(); err != nil {
		return err
	}

	return nil
}
