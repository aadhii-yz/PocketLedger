package collections

import "github.com/pocketbase/pocketbase/core"

func CreateCollections(app core.App) error {
	err := ensureUsersExtended(app)
	return err
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
	return app.Save(col)
}
