package main

import (
	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"log"
)

func main() {
	app := pocketbase.New()

	app.OnBeforeServe().Add(func(e *core.ServeEvent) error {
		// Register custom POS/Billing routes
		// e.Router.Add("POST", "/api/custom/checkout", checkoutHandler(app))
		return nil
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
