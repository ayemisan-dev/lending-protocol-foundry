import { BaseError, ContractFunctionRevertedError, decodeErrorResult, type Abi } from "viem";

/**
 * Extracts a human-readable message from any wagmi/viem error.
 * Priority:
 *   1. Custom contract error name (e.g. "HealthFactorTooLow")
 *   2. Fallback decode using raw signature if errorName is missing
 *   3. shortMessage from viem
 *   4. Generic fallback
 */
export function parseError(error: unknown, abi?: Abi): string | undefined {
    if (!error) return undefined;

    if (error instanceof BaseError) {
        // 1. Try to extract via BaseError.walk
        const revertError = error.walk(
            (err) => err instanceof ContractFunctionRevertedError
        );
        if (revertError instanceof ContractFunctionRevertedError) {
            const name = revertError.data?.errorName;
            if (name) {
                return formatErrorName(name);
            }
        }

        // 2. Fallback: try to decode raw signature from error cause
        //    This handles cases where viem didn't decode automatically.
        const cause = (error as any).cause;
        if (cause?.signature && abi) {
            try {
                const decoded = decodeErrorResult({
                    abi,
                    data: cause.signature,
                });
                return formatErrorName(decoded.errorName);
            } catch {
                // ignore fallback errors
            }
        }

        // 3. Generic viem short message
        if (error.shortMessage) return error.shortMessage;
    }

    // 4. Generic fallback
    if (error instanceof Error) {
        if (error.message.includes("User rejected"))
            return "Transaction rejected in wallet.";
        return error.message;
    }

    return String(error);
}

function formatErrorName(name: string): string {
    const map: Record<string, string> = {
        HealthFactorTooLow:
            "Withdrawal would leave you below the safety threshold.",
        BorrowingCapacityExceeded:
            "Borrow amount exceeds your collateral capacity.",
        InsufficientSupply:
            "Withdraw amount exceeds your supplied balance.",
        InsufficientLiquidity:
            "The pool does not have enough liquidity for this borrow.",
        RepayAmountExceedsDebt: "Repay amount exceeds your outstanding debt.",
        InvalidAmount: "Amount must be greater than zero.",
    };
    return map[name] ?? name;
}