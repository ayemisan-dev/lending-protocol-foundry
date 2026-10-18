import type { Metadata } from "next";
import { Providers } from "@/components/providers";
import "./globals.css";

export const metadata: Metadata = {
    title: "LendX",
    description: "DeFi lending and borrowing protocol on Sepolia",
};

export default function RootLayout({children,}: {children: React.ReactNode;}) {
    return (
        <html lang="en" className="dark">
            <body className="min-h-screen bg-neutral-950 text-neutral-100 antialiased">
                <Providers>{children}</Providers>
            </body>
        </html>
    );
}