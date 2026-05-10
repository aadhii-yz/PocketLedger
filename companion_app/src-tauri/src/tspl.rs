use serde::Deserialize;
use std::collections::HashMap;
use std::io::Write;
use std::net::TcpStream;
use std::time::Duration;

#[derive(Debug, Deserialize)]
pub struct BarcodeData {
    pub name: String,
    pub barcode: String,
    pub sku: String,
    pub selling_price: f64,
    pub show_sku: bool,
    pub show_price: bool,
    pub shop_name: Option<String>,
    pub details: Option<HashMap<String, String>>,
}

pub fn print_barcode(ip: &str, port: u16, data: &BarcodeData) -> Result<(), String> {
    let cmds = build(data);
    send(ip, port, cmds.as_bytes())
}

fn build(d: &BarcodeData) -> String {
    // 50mm x 30mm label at 203 DPI (1mm = 8 dots)
    let mut s = String::new();
    s.push_str("SIZE 50 mm, 30 mm\n");
    s.push_str("GAP 2 mm, 0 mm\n");
    s.push_str("DIRECTION 0\n");
    s.push_str("CLS\n");

    let mut y = 4u32;

    // Optional shop name (small font at top)
    if let Some(shop) = &d.shop_name {
        if !shop.is_empty() {
            s.push_str(&format!("TEXT 4,{y},\"2\",0,1,1,\"{}\"\n", escape(shop)));
            y += 20;
        }
    }

    // Product name (large font, up to 44 chars)
    let name = truncate(&d.name, 44);
    s.push_str(&format!("TEXT 4,{y},\"3\",0,1,1,\"{}\"\n", escape(&name)));
    y += 28;

    // Code128 barcode (48 dots high)
    s.push_str(&format!(
        "BARCODE 4,{y},\"128\",48,1,0,2,2,\"{}\"\n",
        escape(&d.barcode)
    ));
    y += 60;

    // SKU and price on same line
    let mut sub = String::new();
    if d.show_sku && !d.sku.is_empty() {
        sub.push_str(&d.sku);
    }
    if d.show_price {
        if !sub.is_empty() {
            sub.push_str("  ");
        }
        sub.push_str(&format!("Rs.{:.2}", d.selling_price));
    }
    if !sub.is_empty() {
        s.push_str(&format!("TEXT 4,{y},\"2\",0,1,1,\"{}\"\n", escape(&sub)));
        y += 20;
    }

    // Key-value detail attributes
    if let Some(details) = &d.details {
        for (k, v) in details {
            if y + 16 > 240 {
                break;
            }
            let line = format!("{k}: {v}");
            s.push_str(&format!(
                "TEXT 4,{y},\"1\",0,1,1,\"{}\"\n",
                escape(&truncate(&line, 56))
            ));
            y += 16;
        }
    }

    s.push_str("PRINT 1\n");
    s
}

fn send(ip: &str, port: u16, data: &[u8]) -> Result<(), String> {
    let addr = format!("{ip}:{port}");
    let mut stream = TcpStream::connect_timeout(
        &addr.parse().map_err(|e: std::net::AddrParseError| e.to_string())?,
        Duration::from_secs(5),
    )
    .map_err(|e| format!("Cannot connect to barcode printer at {addr}: {e}"))?;
    stream.write_all(data).map_err(|e| e.to_string())?;
    Ok(())
}

fn escape(s: &str) -> String {
    s.replace('"', "'")
}

fn truncate(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_contains_barcode_cmd() {
        let d = BarcodeData {
            name: "Test Product".into(),
            barcode: "0000000042".into(),
            sku: "TST-001".into(),
            selling_price: 99.0,
            show_sku: true,
            show_price: true,
            shop_name: Some("My Shop".into()),
            details: None,
        };
        let out = build(&d);
        assert!(out.contains("BARCODE"));
        assert!(out.contains("0000000042"));
        assert!(out.contains("SIZE 50 mm"));
    }

    #[test]
    fn escape_replaces_double_quotes() {
        assert_eq!(escape("say \"hi\""), "say 'hi'");
    }
}
