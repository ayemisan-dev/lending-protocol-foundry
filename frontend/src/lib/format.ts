import { formatUnits } from "viem";

/** Format a raw token amount into a human-readable string. */
export function formatToken(
    value: bigint | undefined,
    decimals: number = 18,
    fractionDigits: number = 4
): string {
    if (value === undefined) return "—";
    const formatted = formatUnits(value, decimals);
    const [whole, fraction] = formatted.split(".");
    if (!fraction) return whole;
    return `${whole}.${fraction.slice(0, fractionDigits)}`;
}

/** Format an 18-decimal USD value with a $ prefix. */
export function formatUsd(value: bigint | undefined): string {
    if (value === undefined) return "—";
    const formatted = formatUnits(value, 18);
    const [whole, fraction] = formatted.split(".");
    const truncated = fraction ? `${whole}.${fraction.slice(0, 2)}` : whole;
    return `$${truncated}`;
}

/** Format a health factor (18-decimal) for display. */
export function formatHealthFactor(value: bigint | undefined): string {
    if (value === undefined) return "—";
    // type(uint256).max is returned when there is no debt.
    const MAX_UINT256 = 2n ** 256n - 1n;
    if (value === MAX_UINT256) return "∞";
    const formatted = formatUnits(value, 18);
    const [whole, fraction] = formatted.split(".");
    return fraction ? `${whole}.${fraction.slice(0, 2)}` : whole;
}

/** Shorten an address for display. */
export function shortAddress(address: string | undefined): string {
    if (!address) return "—";
    return `${address.slice(0, 6)}…${address.slice(-4)}`;
}