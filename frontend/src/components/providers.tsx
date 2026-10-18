"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { useState, type ReactNode } from "react";
import { wagmiConfig } from "@/config/wagmi";
import { ToastProvider } from "./Toast";
import { TransactionProvider } from "@/context/TransactionProvider";

/**
 * Client-side providers for the app. 
 */
export function Providers({ children }: { children: ReactNode }) {
    const [queryClient] = useState(() => new QueryClient());

    return (
        <WagmiProvider config={wagmiConfig}>
            <QueryClientProvider client={queryClient}>
                <ToastProvider>
                    <TransactionProvider>
                        {children}
                    </TransactionProvider>
                </ToastProvider>
            </QueryClientProvider>
        </WagmiProvider>
    );
}