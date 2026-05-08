import { z } from 'zod';

// ── Enums ─────────────────────────────────────────────────────────────────────

export const UserRoleSchema = z.enum(['admin', 'manager', 'pos', 'stock_entry']);
export const LocationTypeSchema = z.enum(['warehouse', 'shop']);
export const UnitSchema = z.enum(['piece', 'kg', 'litre', 'box']);
export const StockMovementTypeSchema = z.enum([
  'purchase', 'sale', 'adjustment', 'return', 'transfer_in', 'transfer_out',
]);
export const TransferStatusSchema = z.enum(['pending', 'completed', 'cancelled']);
export const PaymentMethodSchema = z.enum(['cash', 'card', 'upi', 'credit']);
export const PaymentStatusSchema = z.enum(['paid', 'pending', 'partial']);
export const LogLevelSchema = z.enum(['INFO', 'WARNING', 'ERROR']);
export const LogSourceSchema = z.enum(['billing', 'stock', 'auth', 'system']);

// ── Collection Schemas (snake_case — matches PocketBase, used for z.infer<>) ──

export const AuthUserSchema = z.object({
  id: z.string(),
  email: z.string().email(),
  role: UserRoleSchema,
  assigned_shop: z.string(),
});

export const LocationSchema = z.object({
  id: z.string(),
  name: z.string(),
  type: LocationTypeSchema.optional(),
  address: z.string().optional(),
  phone: z.string().optional(),
  is_active: z.boolean().optional(),
});

export const CategorySchema = z.object({
  id: z.string(),
  name: z.string(),
  description: z.string().optional(),
});

export const ProductSchema = z.object({
  id: z.string(),
  name: z.string(),
  sku: z.string(),
  barcode: z.string().optional(),
  category: z.string().optional(),
  unit: UnitSchema.optional(),
  cost_price: z.number(),
  selling_price: z.number(),
  tax_rate: z.number().optional(),
  details: z.record(z.string(), z.string()).optional(),
  image: z.string().optional(),
});

export const StockSchema = z.object({
  id: z.string(),
  product: z.string(),
  location: z.string(),
  quantity: z.number(),
  low_stock_threshold: z.number().optional(),
});

export const StockMovementSchema = z.object({
  id: z.string(),
  product: z.string(),
  location: z.string().optional(),
  type: StockMovementTypeSchema,
  quantity: z.number(),
  reference: z.string().optional(),
  note: z.string().optional(),
});

export const StockTransferItemSchema = z.object({
  id: z.string(),
  transfer: z.string(),
  product: z.string().optional(),
  product_name: z.string(),
  quantity: z.number(),
  note: z.string().optional(),
});

export const StockTransferSchema = z.object({
  id: z.string(),
  transfer_number: z.string(),
  from_location: z.string(),
  to_location: z.string(),
  status: TransferStatusSchema,
  notes: z.string().optional(),
  created_by: z.string().optional(),
  created: z.string().optional(),
});

export const BillItemSchema = z.object({
  id: z.string(),
  bill: z.string(),
  product: z.string().optional(),
  product_name: z.string(),
  quantity: z.number(),
  unit_price: z.number(),
  tax_rate: z.number().optional(),
  line_total: z.number(),
});

export const BillSchema = z.object({
  id: z.string(),
  bill_number: z.string(),
  shop: z.string().optional(),
  customer_name: z.string().optional(),
  customer_phone: z.string().optional(),
  items: z.array(z.unknown()).optional(),
  subtotal: z.number(),
  tax_total: z.number().optional(),
  discount: z.number().optional(),
  grand_total: z.number(),
  payment_method: PaymentMethodSchema.optional(),
  payment_status: PaymentStatusSchema.optional(),
  created_by: z.string().optional(),
  notes: z.string().optional(),
  created: z.string().optional(),
});

export const PrintSettingsSchema = z.object({
  shop_name: z.string().optional().default(''),
  shop_address: z.string().optional().default(''),
  shop_phone: z.string().optional().default(''),
  gst_number: z.string().optional().default(''),
  receipt_footer: z.string().optional().default(''),
  show_customer_info: z.boolean().optional().default(false),
  show_tax_breakdown: z.boolean().optional().default(false),
  barcode_show_sku: z.boolean().optional().default(false),
  barcode_show_price: z.boolean().optional().default(false),
  receipt_printer: z.string().optional().default(''),
  label_printer: z.string().optional().default(''),
});

export const SystemLogSchema = z.object({
  id: z.string(),
  level: LogLevelSchema,
  message: z.string(),
  status_code: z.number().optional(),
  details: z.string().optional(),
  source: LogSourceSchema.optional(),
  user_id: z.string().optional(),
  created: z.string().optional(),
});

// ── Inferred Types ────────────────────────────────────────────────────────────

export type UserRole         = z.infer<typeof UserRoleSchema>;
export type LocationType     = z.infer<typeof LocationTypeSchema>;
export type AuthUser         = z.infer<typeof AuthUserSchema>;
export type Location         = z.infer<typeof LocationSchema>;
export type Category         = z.infer<typeof CategorySchema>;
export type Product          = z.infer<typeof ProductSchema>;
export type Stock            = z.infer<typeof StockSchema>;
export type StockMovement    = z.infer<typeof StockMovementSchema>;
export type StockTransferItem = z.infer<typeof StockTransferItemSchema>;
export type StockTransfer    = z.infer<typeof StockTransferSchema>;
export type BillItem         = z.infer<typeof BillItemSchema>;
export type Bill             = z.infer<typeof BillSchema>;
export type PrintSettings    = z.infer<typeof PrintSettingsSchema>;
export type SystemLog        = z.infer<typeof SystemLogSchema>;
export type TransferStatus   = z.infer<typeof TransferStatusSchema>;
export type PaymentMethod    = z.infer<typeof PaymentMethodSchema>;
export type Unit             = z.infer<typeof UnitSchema>;

// ── Form Input Schemas (used with safeParse() before API calls) ───────────────

export const ProductFormSchema = z.object({
  name: z.string().min(1, 'Product name is required'),
  sku: z.string().min(1, 'SKU is required'),
  barcode: z.string().optional(),
  categoryId: z.string().min(1, 'Category is required'),
  unit: UnitSchema.optional(),
  sellingPrice: z.coerce
    .number({ invalid_type_error: 'Selling price must be a number' })
    .nonnegative('Selling price cannot be negative'),
  costPrice: z.coerce
    .number({ invalid_type_error: 'Cost price must be a number' })
    .nonnegative('Cost price cannot be negative'),
  taxRate: z.coerce.number().min(0).max(100).default(0),
});

export const UserFormSchema = z.object({
  email: z.string().min(1, 'Email is required').email('Invalid email address'),
  fullName: z.string().min(1, 'Full name is required'),
  role: UserRoleSchema,
  password: z.string().optional(),
  assignedShop: z.string().optional(),
});

export const UserCreateFormSchema = UserFormSchema.extend({
  password: z.string().min(6, 'Password must be at least 6 characters'),
});

export const StockAdjustFormSchema = z.object({
  productId: z.string().min(1, 'Please select a product'),
  quantity: z.coerce
    .number({ invalid_type_error: 'Quantity must be a number' })
    .refine(q => q !== 0, { message: 'Quantity cannot be zero' }),
  type: StockMovementTypeSchema,
  note: z.string().optional(),
});

export const TransferItemFormSchema = z.object({
  product_id: z.string().min(1, 'Select a product for each item'),
  quantity: z.coerce.number().positive('Item quantity must be greater than 0'),
  note: z.string().optional(),
});

export const TransferFormSchema = z.object({
  from_location: z.string().min(1, 'Source location is required'),
  to_location: z.string().min(1, 'Destination location is required'),
  notes: z.string().optional(),
  items: z.array(TransferItemFormSchema).min(1, 'At least one transfer item is required'),
}).refine(
  d => d.from_location !== d.to_location,
  { message: 'Source and destination must be different', path: ['to_location'] },
);

// ── Utility ───────────────────────────────────────────────────────────────────

/** Returns the first human-readable error message from a failed safeParse. */
export function firstError(error: z.ZodError): string {
  return error.errors[0]?.message ?? 'Validation failed';
}
