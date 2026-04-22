package services

import (
	"fmt"

	"github.com/pocketbase/pocketbase/core"
)

type DashboardStats struct {
	TodayRevenue   float64       `json:"today_revenue"`
	WeekRevenue    float64       `json:"week_revenue"`
	MonthRevenue   float64       `json:"month_revenue"`
	TopProducts    []TopProduct  `json:"top_products"`
	PaymentMethods []PaymentStat `json:"payment_methods"`
}

type TopProduct struct {
	ProductID   string  `json:"product_id"   db:"product_id"`
	ProductName string  `json:"product_name" db:"product_name"`
	TotalQty    float64 `json:"total_qty"    db:"total_qty"`
	TotalRev    float64 `json:"total_rev"    db:"total_rev"`
}

type PaymentStat struct {
	Method string  `json:"method" db:"payment_method"`
	Total  float64 `json:"total"  db:"total"`
	Count  int     `json:"count"  db:"count"`
}

type LowStockItem struct {
	ProductID   string  `json:"product_id"          db:"product_id"`
	ProductName string  `json:"product_name"        db:"product_name"`
	Quantity    float64 `json:"quantity"            db:"quantity"`
	Threshold   float64 `json:"low_stock_threshold" db:"low_stock_threshold"`
}

type revenueResult struct {
	Total float64 `db:"total"`
}

func GetDashboard(app core.App) (*DashboardStats, error) {
	db := app.DB()
	stats := &DashboardStats{}

	revenueQueries := []struct {
		dest  *float64
		where string
	}{
		{&stats.TodayRevenue, "DATE(created) = DATE('now')"},
		{&stats.WeekRevenue, "created >= DATE('now', '-7 days')"},
		{&stats.MonthRevenue, "strftime('%Y-%m', created) = strftime('%Y-%m', 'now')"},
	}
	for _, q := range revenueQueries {
		var r revenueResult
		if err := db.NewQuery(fmt.Sprintf(`
			SELECT COALESCE(SUM(grand_total), 0) AS total
			FROM bills WHERE payment_status = 'paid' AND %s`, q.where,
		)).One(&r); err != nil {
			return nil, err
		}
		*q.dest = r.Total
	}

	if err := db.NewQuery(`
		SELECT
			bi.product        AS product_id,
			bi.product_name,
			SUM(bi.quantity)   AS total_qty,
			SUM(bi.line_total) AS total_rev
		FROM bill_items bi
		JOIN bills b ON b.id = bi.bill
		WHERE b.payment_status = 'paid'
		  AND strftime('%Y-%m', b.created) = strftime('%Y-%m', 'now')
		GROUP BY bi.product, bi.product_name
		ORDER BY total_rev DESC
		LIMIT 10
	`).All(&stats.TopProducts); err != nil {
		return nil, err
	}

	if err := db.NewQuery(`
		SELECT
			payment_method,
			COALESCE(SUM(grand_total), 0) AS total,
			COUNT(*) AS count
		FROM bills
		WHERE payment_status = 'paid'
		  AND strftime('%Y-%m', created) = strftime('%Y-%m', 'now')
		GROUP BY payment_method
	`).All(&stats.PaymentMethods); err != nil {
		return nil, err
	}

	return stats, nil
}

func GetLowStock(app core.App) ([]LowStockItem, error) {
	var items []LowStockItem
	err := app.DB().NewQuery(`
		SELECT
			s.product       AS product_id,
			p.name          AS product_name,
			s.quantity,
			s.low_stock_threshold
		FROM stock s
		JOIN products p ON p.id = s.product
		WHERE s.low_stock_threshold > 0
		  AND s.quantity <= s.low_stock_threshold
		ORDER BY (s.quantity - s.low_stock_threshold) ASC
	`).All(&items)
	return items, err
}

func NextBillNumber(app core.App) (string, error) {
	type countResult struct {
		Count int `db:"count"`
	}
	var r countResult
	if err := app.DB().
		NewQuery("SELECT COUNT(*) AS count FROM bills").
		One(&r); err != nil {
		return "", err
	}
	return fmt.Sprintf("INV-%04d", r.Count+1), nil
}
