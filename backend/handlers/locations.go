package handlers

import (
	"net/http"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// ListLocations returns all active locations. Optional ?type=shop|warehouse filter.
func ListLocations(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		locType := e.Request.URL.Query().Get("type")

		var filter string
		var params dbx.Params
		if locType == "warehouse" || locType == "shop" {
			filter = "is_active = true && type = {:type}"
			params = dbx.Params{"type": locType}
		} else {
			filter = "is_active = true"
			params = dbx.Params{}
		}

		records, err := app.FindRecordsByFilter("locations", filter, "name", 0, 0, params)
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}

		result := make([]map[string]any, 0, len(records))
		for _, r := range records {
			result = append(result, map[string]any{
				"id":       r.Id,
				"name":     r.GetString("name"),
				"type":     r.GetString("type"),
				"address":  r.GetString("address"),
				"phone":    r.GetString("phone"),
				"is_active": r.GetBool("is_active"),
			})
		}
		return e.JSON(http.StatusOK, result)
	}
}

type createLocationRequest struct {
	Name     string `json:"name"`
	Type     string `json:"type"`
	Address  string `json:"address"`
	Phone    string `json:"phone"`
	IsActive *bool  `json:"is_active"`
}

// CreateLocation creates a new shop or warehouse location.
// Only one warehouse is allowed system-wide; enforced here.
func CreateLocation(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		var req createLocationRequest
		if err := e.BindBody(&req); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}
		if req.Name == "" {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "name is required"})
		}
		if req.Type != "warehouse" && req.Type != "shop" {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "type must be 'warehouse' or 'shop'"})
		}

		// Enforce single-warehouse rule.
		if req.Type == "warehouse" {
			type countResult struct {
				Count int `db:"count"`
			}
			var r countResult
			if err := app.DB().
				NewQuery("SELECT COUNT(*) AS count FROM locations WHERE type = 'warehouse'").
				One(&r); err != nil {
				return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
			}
			if r.Count >= 1 {
				return e.JSON(http.StatusUnprocessableEntity, map[string]string{
					"message": "only one warehouse is allowed",
				})
			}
		}

		locCol, err := app.FindCollectionByNameOrId("locations")
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		rec := core.NewRecord(locCol)
		rec.Set("name", req.Name)
		rec.Set("type", req.Type)
		rec.Set("address", req.Address)
		rec.Set("phone", req.Phone)
		isActive := true
		if req.IsActive != nil {
			isActive = *req.IsActive
		}
		rec.Set("is_active", isActive)

		if err := app.Save(rec); err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusCreated, map[string]any{
			"id":       rec.Id,
			"name":     rec.GetString("name"),
			"type":     rec.GetString("type"),
			"is_active": rec.GetBool("is_active"),
		})
	}
}

type updateLocationRequest struct {
	Name     *string `json:"name"`
	Address  *string `json:"address"`
	Phone    *string `json:"phone"`
	IsActive *bool   `json:"is_active"`
}

// UpdateLocation patches mutable fields on an existing location.
// Changing the type field is not allowed.
func UpdateLocation(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		id := e.Request.PathValue("id")

		rec, err := app.FindRecordById("locations", id)
		if err != nil {
			return e.JSON(http.StatusNotFound, map[string]string{"message": "location not found"})
		}

		// Reject type changes.
		var body map[string]any
		if err := e.BindBody(&body); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}
		if _, hasType := body["type"]; hasType {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "changing location type is not allowed"})
		}

		var req updateLocationRequest
		if err := e.BindBody(&req); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}

		if req.Name != nil {
			rec.Set("name", *req.Name)
		}
		if req.Address != nil {
			rec.Set("address", *req.Address)
		}
		if req.Phone != nil {
			rec.Set("phone", *req.Phone)
		}
		if req.IsActive != nil {
			rec.Set("is_active", *req.IsActive)
		}

		if err := app.Save(rec); err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, map[string]any{
			"id":       rec.Id,
			"name":     rec.GetString("name"),
			"type":     rec.GetString("type"),
			"address":  rec.GetString("address"),
			"phone":    rec.GetString("phone"),
			"is_active": rec.GetBool("is_active"),
		})
	}
}
