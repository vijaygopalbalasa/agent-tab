import type { Amount } from '@/onchain-money'

/** Every significant digit, and at least two decimals: 0.015 stays 0.015, 0.1 shows as 0.10. */
export function usdcText(a: Amount): string {
  const [whole, frac = ''] = a.toString().split('.')
  return `${whole}.${frac.padEnd(2, '0')}`
}
