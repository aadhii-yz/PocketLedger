use serde::Deserialize;
use std::io::Write;
use std::net::TcpStream;
use std::time::Duration;

// 80mm printer — 42 chars per line at standard font
const LINE_WIDTH: usize = 42;

#[derive(Debug, Deserialize, Clone)]
pub struct ReceiptItem {
    pub name: String,
    pub qty: f64,
    pub unit_price: f64,
}

#[derive(Debug, Deserialize)]
pub struct ReceiptData {
    pub shop_name: String,
    pub shop_address: Option<String>,
    pub shop_phone: Option<String>,
    pub gst_number: Option<String>,
    pub date: String,
    pub bill_number: String,
    pub items: Vec<ReceiptItem>,
    pub subtotal: f64,
    pub tax_total: f64,
    pub discount: f64,
    pub grand_total: f64,
    pub show_tax_breakdown: bool,
    pub show_customer_info: bool,
    pub payment_method: String,
    pub customer_name: Option<String>,
    pub customer_phone: Option<String>,
    pub receipt_footer: Option<String>,
}

pub fn print_receipt(ip: &str, port: u16, data: &ReceiptData) -> Result<(), String> {
    let bytes = build(data);
    send(ip, port, &bytes)
}

fn build(d: &ReceiptData) -> Vec<u8> {
    let mut b: Vec<u8> = Vec::new();

    // Init + center
    b.extend_from_slice(b"\x1b\x40"); // ESC @ — init
    b.extend_from_slice(b"\x1b\x61\x01"); // ESC a 1 — center

    // Shop name: bold + double-width
    b.extend_from_slice(b"\x1b\x45\x01"); // bold on
    b.extend_from_slice(b"\x1d\x21\x11"); // double width+height
    b.extend_from_slice(d.shop_name.as_bytes());
    b.extend_from_slice(b"\n");
    b.extend_from_slice(b"\x1d\x21\x00"); // normal size
    b.extend_from_slice(b"\x1b\x45\x00"); // bold off

    if let Some(addr) = &d.shop_address {
        if !addr.is_empty() {
            b.extend_from_slice(addr.as_bytes());
            b.push(b'\n');
        }
    }
    if let Some(phone) = &d.shop_phone {
        if !phone.is_empty() {
            b.extend_from_slice(phone.as_bytes());
            b.push(b'\n');
        }
    }
    if let Some(gst) = &d.gst_number {
        if !gst.is_empty() {
            b.extend_from_slice(format!("GST: {gst}").as_bytes());
            b.push(b'\n');
        }
    }

    b.extend_from_slice(b"\x1b\x61\x00"); // left align
    b.extend_from_slice(divider().as_bytes());

    // Bill info
    b.extend_from_slice(format!("Bill No: {}\n", d.bill_number).as_bytes());
    b.extend_from_slice(format!("Date   : {}\n", format_date(&d.date)).as_bytes());
    b.extend_from_slice(divider().as_bytes());

    // Items header
    b.extend_from_slice(b"\x1b\x45\x01"); // bold on
    b.extend_from_slice(col4("Item", "Qty", "Rate", "Amt").as_bytes());
    b.extend_from_slice(b"\x1b\x45\x00"); // bold off
    b.extend_from_slice(divider().as_bytes());

    for item in &d.items {
        let amt = item.qty * item.unit_price;
        b.extend_from_slice(col4(
            &truncate(&item.name, 18),
            &format!("{:.0}", item.qty),
            &format!("{:.2}", item.unit_price),
            &format!("{:.2}", amt),
        ).as_bytes());
    }

    b.extend_from_slice(divider().as_bytes());

    // Totals
    b.extend_from_slice(right_pair("Subtotal", &format!("{:.2}", d.subtotal)).as_bytes());
    if d.show_tax_breakdown && d.tax_total > 0.0 {
        b.extend_from_slice(right_pair("GST", &format!("{:.2}", d.tax_total)).as_bytes());
    }
    if d.discount > 0.0 {
        b.extend_from_slice(right_pair("Discount", &format!("-{:.2}", d.discount)).as_bytes());
    }
    b.extend_from_slice(b"\x1b\x45\x01"); // bold
    b.extend_from_slice(right_pair("TOTAL", &format!("{:.2}", d.grand_total)).as_bytes());
    b.extend_from_slice(b"\x1b\x45\x00");

    b.extend_from_slice(divider().as_bytes());
    b.extend_from_slice(format!("Payment: {}\n", d.payment_method).as_bytes());

    if d.show_customer_info {
        if let Some(name) = &d.customer_name {
            if !name.is_empty() {
                b.extend_from_slice(format!("Customer: {name}\n").as_bytes());
            }
        }
        if let Some(phone) = &d.customer_phone {
            if !phone.is_empty() {
                b.extend_from_slice(format!("Phone   : {phone}\n").as_bytes());
            }
        }
    }

    if let Some(footer) = &d.receipt_footer {
        if !footer.is_empty() {
            b.extend_from_slice(divider().as_bytes());
            b.extend_from_slice(b"\x1b\x61\x01"); // center
            b.extend_from_slice(footer.as_bytes());
            b.push(b'\n');
            b.extend_from_slice(b"\x1b\x61\x00");
        }
    }

    // Feed + cut
    b.extend_from_slice(b"\n\n\n\n");
    b.extend_from_slice(b"\x1d\x56\x41\x00"); // GS V A 0 — partial cut

    b
}

fn send(ip: &str, port: u16, data: &[u8]) -> Result<(), String> {
    let addr = format!("{ip}:{port}");
    let mut stream = TcpStream::connect_timeout(
        &addr.parse().map_err(|e: std::net::AddrParseError| e.to_string())?,
        Duration::from_secs(5),
    )
    .map_err(|e| format!("Cannot connect to receipt printer at {addr}: {e}"))?;
    stream.write_all(data).map_err(|e| e.to_string())?;
    Ok(())
}

fn divider() -> String {
    format!("{}\n", "-".repeat(LINE_WIDTH))
}

// 4-column row: name(18) qty(5) rate(9) amt(10)
fn col4(name: &str, qty: &str, rate: &str, amt: &str) -> String {
    format!(
        "{:<18}{:>5}{:>9}{:>10}\n",
        truncate(name, 18),
        truncate(qty, 5),
        truncate(rate, 9),
        truncate(amt, 10)
    )
}

fn right_pair(label: &str, value: &str) -> String {
    let pad = LINE_WIDTH.saturating_sub(label.len() + value.len());
    format!("{}{}{}\n", label, " ".repeat(pad), value)
}

fn truncate(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

fn format_date(iso: &str) -> String {
    // Take the date part only (2024-01-15T... → 2024-01-15)
    iso.chars().take(10).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> ReceiptData {
        ReceiptData {
            shop_name: "Test Shop".into(),
            shop_address: Some("123 Main St".into()),
            shop_phone: Some("9876543210".into()),
            gst_number: Some("29ABCDE1234F1Z1".into()),
            date: "2024-01-15T10:30:00Z".into(),
            bill_number: "INV-0001".into(),
            items: vec![ReceiptItem { name: "Widget".into(), qty: 2.0, unit_price: 50.0 }],
            subtotal: 100.0,
            tax_total: 18.0,
            discount: 0.0,
            grand_total: 118.0,
            show_tax_breakdown: true,
            show_customer_info: false,
            payment_method: "CASH".into(),
            customer_name: None,
            customer_phone: None,
            receipt_footer: Some("Thank you!".into()),
        }
    }

    #[test]
    fn build_contains_init_and_cut() {
        let bytes = build(&sample());
        // ESC @ init
        assert!(bytes.windows(2).any(|w| w == [0x1b, 0x40]));
        // GS V cut
        assert!(bytes.windows(4).any(|w| w == [0x1d, 0x56, 0x41, 0x00]));
    }

    #[test]
    fn build_contains_shop_name() {
        let bytes = build(&sample());
        let text = String::from_utf8_lossy(&bytes);
        assert!(text.contains("Test Shop"));
        assert!(text.contains("INV-0001"));
    }
}
