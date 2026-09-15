import pricingData from './model-pricing.json';

export interface ModelPrice {
  input: number;
  cached_input: number;
  output: number;
}

export interface PricingConfig {
  models: Record<string, ModelPrice>;
}

export interface TokenUsage {
  input_raw?: number;
  input?: number;
  cached?: number;
  output?: number;
}

export const builtinPrices: Record<string, ModelPrice> = pricingData.models;
export const pricingSource = pricingData.source;
export const pricingVerifiedAt = pricingData.verified_at;
const aliases: Record<string, string> = {
  astra: 'gpt-6-astra', sol: 'gpt-5.6-sol', terra: 'gpt-5.6-terra', luna: 'gpt-5.6-luna',
};

export function isModelPrice(value: unknown): value is ModelPrice {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const price = value as Record<string, unknown>;
  return Object.keys(price).length === 3 && ['input', 'cached_input', 'output'].every((key) =>
    typeof price[key] === 'number' && Number.isFinite(price[key]) && price[key] >= 0 && price[key] <= 1e6);
}

export function validPriceModel(model: string) {
  return /^[a-z0-9][a-z0-9._:/-]{0,127}$/.test(model);
}

export function resolveModelPrice(model?: string, pricing?: PricingConfig): ModelPrice | undefined {
  if (!model?.trim()) return undefined;
  const full = model.trim().toLowerCase();
  const bare = full.slice(full.lastIndexOf('/') + 1);
  const base = bare.replace(/-\d{4}-\d{2}-\d{2}$/, '');
  const canonical = Object.prototype.hasOwnProperty.call(aliases, base) ? aliases[base] : base;
  const candidates = [...new Set([full, bare, base, canonical])];
  for (const prices of [pricing?.models ?? {}, builtinPrices]) {
    for (const key of candidates) {
      if (Object.prototype.hasOwnProperty.call(prices, key) && isModelPrice(prices[key])) return prices[key];
    }
  }
  return undefined;
}

function tokenCount(value?: number): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : undefined;
}

export function usageCounts(usage: TokenUsage) {
  const cached = tokenCount(usage.cached) ?? 0;
  const input = tokenCount(usage.input_raw) ?? (tokenCount(usage.input) === undefined ? undefined : tokenCount(usage.input)! + cached);
  return {input, cached: input === undefined ? cached : Math.min(cached, input), output: tokenCount(usage.output)};
}

export function cacheRate(usage: TokenUsage): number | undefined {
  const counts = usageCounts(usage);
  return counts.input ? Math.round(counts.cached / counts.input * 1000) / 10 : undefined;
}

export function estimateCost(model: string | undefined, usage: TokenUsage, pricing?: PricingConfig): number | undefined {
  const price = resolveModelPrice(model, pricing);
  const counts = usageCounts(usage);
  if (!price || counts.input === undefined || counts.output === undefined) return undefined;
  const cost = ((counts.input - counts.cached) * price.input + counts.cached * price.cached_input + counts.output * price.output) / 1e6;
  return Number.isFinite(cost) ? cost : undefined;
}

export function costText(cost?: number): string {
  if (cost === undefined) return 'Cost —';
  if (cost > 0 && cost < 0.01) return 'Cost <$0.01';
  return `Cost ~$${(Math.round(cost * 100 + 1e-9) / 100).toFixed(2)}`;
}
