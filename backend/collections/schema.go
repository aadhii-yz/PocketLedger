package collections

import (
	"github.com/pocketbase/pocketbase/core"
)

func CreateCollections(app core.App) error {
	for _, fn := range []func(core.App) error{
		ensureUsersExtended,
		ensureCategories,
		ensureProducts,
		ensureStock,
		ensureStockMovements,
		ensureBills,
		ensureBillItems,
		ensureSystemLogs,
	} {
		if err := fn(app); err != nil {
			return err
		}
	}
	return nil
}

func ensureUsersExtended(app core.App) error {
	col, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		return err
	}

	if col.Fields.GetByName("role") != nil {
		return nil // already extended
	}

	col.Fields.Add(&core.SelectField{
		Name:      "role",
		Required:  true,
		MaxSelect: 1,
		Values:    []string{"admin", "manager", "pos", "stock_entry"},
	})

	apiRule := "@request.auth.role = 'admin' || @request.auth.role = 'manager'"
	col.ListRule = &apiRule
	col.ViewRule = &apiRule
	col.CreateRule = &apiRule
	col.UpdateRule = &apiRule
	col.DeleteRule = &apiRule

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
	if _, err := app.FindCollectionByNameOrId("products"); err == nil {
		return nil
	}
	editRole := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'"
	col := core.NewBaseCollection("products")
	col.ListRule = new("@request.auth.id != ''")
	col.ViewRule = new("@request.auth.id != ''")
	col.CreateRule = new(editRole)
	col.UpdateRule = new(editRole)
	col.DeleteRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")

	categoriesCol, _ := app.FindCollectionByNameOrId("categories")
	var categoryColId string
	if categoriesCol != nil {
		categoryColId = categoriesCol.Id
	}

	col.Fields.Add(&core.TextField{Name: "name", Required: true})
	col.Fields.Add(&core.TextField{Name: "sku", Required: true})
	col.Fields.Add(&core.TextField{Name: "barcode"})
	col.Fields.Add(&core.RelationField{
		Name:         "category",
		CollectionId: categoryColId,
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
	col.Fields.Add(&core.FileField{
		Name:      "image",
		MaxSelect: 1,
		MaxSize:   5242880,
	})
	return app.Save(col)
}

func ensureStock(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("stock"); err == nil {
		return nil
	}
	editRole := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'"

	productsCol, _ := app.FindCollectionByNameOrId("products")
	var productsColId string
	if productsCol != nil {
		productsColId = productsCol.Id
	}

	col := core.NewBaseCollection("stock")
	col.ListRule = new("@request.auth.id != ''")
	col.ViewRule = new("@request.auth.id != ''")
	col.CreateRule = new(editRole)
	col.UpdateRule = new(editRole)
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.RelationField{
		Name:         "product",
		Required:     true,
		CollectionId: productsColId,
		MaxSelect:    1,
	})
	col.Fields.Add(&core.NumberField{Name: "quantity", Required: true})
	col.Fields.Add(&core.NumberField{Name: "low_stock_threshold"})
	return app.Save(col)
}

func ensureStockMovements(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("stock_movements"); err == nil {
		return nil
	}
	viewRole := "@request.auth.role = 'admin' || @request.auth.role = 'manager' || @request.auth.role = 'stock_entry'"

	productsCol, _ := app.FindCollectionByNameOrId("products")
	var productsColId string
	if productsCol != nil {
		productsColId = productsCol.Id
	}

	col := core.NewBaseCollection("stock_movements")
	col.ListRule = new(viewRole)
	col.ViewRule = new(viewRole)
	col.CreateRule = new("@request.auth.id != ''")
	col.UpdateRule = new("@request.auth.role = 'admin'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.RelationField{
		Name:         "product",
		Required:     true,
		CollectionId: productsColId,
		MaxSelect:    1,
	})
	col.Fields.Add(&core.SelectField{
		Name:      "type",
		Required:  true,
		MaxSelect: 1,
		Values:    []string{"purchase", "sale", "adjustment", "return"},
	})
	col.Fields.Add(&core.NumberField{Name: "quantity", Required: true})
	col.Fields.Add(&core.TextField{Name: "reference"})
	col.Fields.Add(&core.TextField{Name: "note"})
	return app.Save(col)
}

func ensureBills(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("bills"); err == nil {
		return nil
	}
	viewRule := "@request.auth.id != '' && (@request.auth.role = 'admin' || @request.auth.role = 'manager' || created_by = @request.auth.id)"

	usersCol, _ := app.FindCollectionByNameOrId("users")
	var usersColId string
	if usersCol != nil {
		usersColId = usersCol.Id
	}

	col := core.NewBaseCollection("bills")
	col.ListRule = new(viewRule)
	col.ViewRule = new(viewRule)
	col.CreateRule = new("@request.auth.id != ''")
	col.UpdateRule = new("@request.auth.role = 'admin' || @request.auth.role = 'manager'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.TextField{Name: "bill_number", Required: true})
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
		CollectionId: usersColId,
		MaxSelect:    1,
	})
	col.Fields.Add(&core.TextField{Name: "notes"})
	return app.Save(col)
}

func ensureBillItems(app core.App) error {
	if _, err := app.FindCollectionByNameOrId("bill_items"); err == nil {
		return nil
	}
	billsCol, _ := app.FindCollectionByNameOrId("bills")
	var billsColId string
	if billsCol != nil {
		billsColId = billsCol.Id
	}

	productsCol, _ := app.FindCollectionByNameOrId("products")
	var productsColId string
	if productsCol != nil {
		productsColId = productsCol.Id
	}

	col := core.NewBaseCollection("bill_items")
	col.ListRule = new("@request.auth.id != ''")
	col.ViewRule = new("@request.auth.id != ''")
	col.CreateRule = new("@request.auth.id != ''")
	col.UpdateRule = new("@request.auth.role = 'admin'")
	col.DeleteRule = new("@request.auth.role = 'admin'")
	col.Fields.Add(&core.RelationField{
		Name:         "bill",
		Required:     true,
		CollectionId: billsColId,
		MaxSelect:    1,
	})
	col.Fields.Add(&core.RelationField{
		Name:         "product",
		CollectionId: productsColId,
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
	if _, err := app.FindCollectionByNameOrId("system_logs"); err == nil {
		return nil
	}
	col := core.NewBaseCollection("system_logs")
	col.ListRule = new("@request.auth.role = 'admin'")
	col.ViewRule = new("@request.auth.role = 'admin'")
	col.CreateRule = new("@request.auth.id != ''")
	col.UpdateRule = nil
	col.DeleteRule = new("@request.auth.role = 'admin'")

	col.Fields.Add(&core.AutodateField{
		Name:     "created",
		OnCreate: true,
	})
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
	return app.Save(col)
}
