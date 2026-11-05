"use client";

import {
    createContext,
    useContext,
    useState,
    useEffect,
    useCallback,
} from "react";
import { createPortal } from "react-dom";

type ToastType = "success" | "error" | "info";

interface ToastItem {
    id: string;
    message: string;
    type: ToastType;
}

const ToastContext = createContext<{
    addToast: (message: string, type?: ToastType) => void;
} | null>(null);

export function ToastProvider({ children }: { children: React.ReactNode }) {
    const [toasts, setToasts] = useState<ToastItem[]>([]);
    const [mounted, setMounted] = useState(false);

    useEffect(() => {
        setMounted(true);
    }, []);

    const addToast = useCallback(
        (message: string, type: ToastType = "info") => {
            const id = Math.random().toString(36).slice(2);
            setToasts((prev) => [...prev, { id, message, type }]);

            setTimeout(() => {
                setToasts((prev) => prev.filter((t) => t.id !== id));
            }, 5000);
        },
        []
    );

    return (
        <ToastContext.Provider value={{ addToast }}>
            {children}
            {}
            {mounted &&
                createPortal(
                    <div className="fixed bottom-6 right-6 z-50 flex flex-col gap-2">
                        {toasts.map((t) => (
                            <div
                                key={t.id}
                                className={`rounded-xl px-4 py-3 shadow-lg border text-sm font-medium transition-all ${
                                    t.type === "success"
                                        ? "bg-emerald-900/90 text-emerald-200 border-emerald-800"
                                        : t.type === "error"
                                          ? "bg-red-900/90 text-red-200 border-red-800"
                                          : "bg-neutral-800/90 text-neutral-200 border-neutral-700"
                                }`}
                            >
                                {t.message}
                            </div>
                        ))}
                    </div>,
                    document.body
                )}
        </ToastContext.Provider>
    );
}

export const useToast = () => {
    const ctx = useContext(ToastContext);
    if (!ctx) throw new Error("useToast must be used within ToastProvider");
    return ctx;
};