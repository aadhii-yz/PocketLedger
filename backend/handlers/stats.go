package handlers

import (
	"net/http"

	"github.com/aadhii-yz/PocketLedger/backend/services"
	"github.com/pocketbase/pocketbase/core"
)

func Dashboard(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		stats, err := services.GetDashboard(app)
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, stats)
	}
}
