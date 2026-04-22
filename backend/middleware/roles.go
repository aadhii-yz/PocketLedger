package middleware

import (
	"net/http"
	"slices"

	"github.com/pocketbase/pocketbase/core"
)

// RequireRole returns a middleware that checks the auth record's role field.
// Must be used after apis.RequireAuth() so e.Auth is already populated.
func RequireRole(roles ...string) func(*core.RequestEvent) error {
	return func(e *core.RequestEvent) error {
		if e.Auth == nil {
			return e.JSON(http.StatusUnauthorized, map[string]string{"message": "unauthorized"})
		}

		userRole := e.Auth.GetString("role")
		if slices.Contains(roles, userRole) {
			return e.Next()
		}

		return e.JSON(http.StatusForbidden, map[string]string{
			"message": "insufficient role",
		})
	}
}
