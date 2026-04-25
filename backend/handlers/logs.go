package handlers

import (
	"net/http"

	"github.com/pocketbase/pocketbase/core"
)

type CreateLogRequest struct {
	Level      string `json:"level"`
	Message    string `json:"message"`
	StatusCode int    `json:"status_code"`
	Details    string `json:"details"`
	Source     string `json:"source"`
}

// CreateLog stores a system log entry written by the frontend.
func CreateLog(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		var req CreateLogRequest
		if err := e.BindBody(&req); err != nil {
			return e.JSON(http.StatusBadRequest, map[string]string{"message": "invalid request body"})
		}
		if req.Level == "" {
			req.Level = "INFO"
		}
		if req.Source == "" {
			req.Source = "system"
		}

		col, err := app.FindCollectionByNameOrId("system_logs")
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": "logs collection not found"})
		}
		rec := core.NewRecord(col)
		rec.Set("level", req.Level)
		rec.Set("message", req.Message)
		rec.Set("status_code", req.StatusCode)
		rec.Set("details", req.Details)
		rec.Set("source", req.Source)
		if e.Auth != nil {
			rec.Set("user_id", e.Auth.Id)
		}
		if err := app.Save(rec); err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusCreated, map[string]string{"status": "ok"})
	}
}

// GetLogs returns system logs ordered by newest first.
func GetLogs(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		records, err := app.FindRecordsByFilter(
			"system_logs", "id != ''", "-created", 200, 0,
		)
		if err != nil {
			return e.JSON(http.StatusInternalServerError, map[string]string{"message": err.Error()})
		}
		return e.JSON(http.StatusOK, records)
	}
}
