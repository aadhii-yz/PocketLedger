package handlers

import "github.com/pocketbase/pocketbase/core"

func Dashboard(app core.App) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		return nil
	}
}
