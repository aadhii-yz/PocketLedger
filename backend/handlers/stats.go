package handlers

import (
	"net/http"

	"github.com/aadhii-yz/PocketLedger/backend/services"
	"github.com/pocketbase/pocketbase/core"
)

func Dashboard(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		shopId := e.Request.URL.Query().Get("shop_id")
		stats, err := services.GetDashboard(app, shopId)
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, stats)
	}
}
