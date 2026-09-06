"use client";

import { useState, useRef, useEffect } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MessageSquare, X, Send, Sparkles, Bot, User, ArrowUpRight } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { askAssistantAction, type AssistantProperty } from "@/lib/actions/assistant";

interface Message {
  id: string;
  role: "user" | "assistant";
  content: string;
  properties?: AssistantProperty[];
  searchHref?: string;
}

const SUGGESTIONS = [
  "2 bedroom in Makutano under 30k",
  "Bedsitter near MUST",
  "Shop to let in Meru Town",
];

const GREETING: Message = {
  id: "greeting",
  role: "assistant",
  content:
    "Hi there! I'm your Kheja_Link assistant. Tell me your budget, the area and the kind of house you want, and I'll search every live listing for you.",
};

export default function AIChatAssistant() {
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([GREETING]);
  const [inputValue, setInputValue] = useState("");
  const [isTyping, setIsTyping] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isTyping, isOpen]);

  useEffect(() => {
    if (!isOpen) return;
    const onKey = (event: KeyboardEvent) => event.key === "Escape" && setIsOpen(false);
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [isOpen]);

  const send = async (raw: string) => {
    const text = raw.trim();
    if (!text || isTyping) return;

    setMessages((prev) => [...prev, { id: `u-${Date.now()}`, role: "user", content: text }]);
    setInputValue("");
    setIsTyping(true);

    try {
      const reply = await askAssistantAction(text);
      setMessages((prev) => [
        ...prev,
        {
          id: `a-${Date.now()}`,
          role: "assistant",
          content: reply.message,
          properties: reply.properties,
          searchHref: reply.searchHref,
        },
      ]);
    } catch {
      setMessages((prev) => [
        ...prev,
        {
          id: `a-${Date.now()}`,
          role: "assistant",
          content: "Sorry, I could not reach the listings just then. Please try again in a moment.",
        },
      ]);
    } finally {
      setIsTyping(false);
      inputRef.current?.focus();
    }
  };

  return (
    <>
      {/* FAB Button */}
      <motion.button
        initial={{ scale: 0, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        whileHover={{ scale: 1.1 }}
        whileTap={{ scale: 0.9 }}
        onClick={() => setIsOpen(true)}
        aria-label="Open the Kheja_Link assistant"
        className="fixed bottom-6 right-6 w-16 h-16 bg-blue-600 text-white rounded-2xl shadow-2xl flex items-center justify-center z-50 group border-4 border-white dark:border-zinc-900"
      >
        <MessageSquare className="w-8 h-8 group-hover:rotate-12 transition-transform" />
        <span className="absolute -top-2 -right-2 w-5 h-5 bg-emerald-500 rounded-full border-2 border-white dark:border-zinc-900 animate-pulse" />
      </motion.button>

      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: 100, scale: 0.8, filter: "blur(10px)" }}
            animate={{ opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }}
            exit={{ opacity: 0, y: 100, scale: 0.8, filter: "blur(10px)" }}
            transition={{ type: "spring", damping: 25, stiffness: 200 }}
            role="dialog"
            aria-label="Kheja_Link assistant"
            className="fixed bottom-24 right-6 w-[90vw] md:w-[400px] h-[600px] max-h-[calc(100vh-8rem)] bg-white dark:bg-zinc-900 rounded-[2.5rem] shadow-[0_32px_64px_-16px_rgba(0,0,0,0.2)] dark:shadow-[0_32px_64px_-16px_rgba(0,0,0,0.5)] border border-zinc-200 dark:border-zinc-800 flex flex-col z-50 overflow-hidden"
          >
            {/* Header */}
            <div className="p-6 bg-zinc-900 dark:bg-black text-white flex items-center justify-between relative overflow-hidden shrink-0">
              <div className="absolute inset-0 opacity-20 bg-[radial-gradient(circle_at_top_right,_var(--tw-gradient-stops))] from-blue-500 via-transparent to-transparent" />
              <div className="relative flex items-center gap-4">
                <div className="w-12 h-12 bg-blue-600 rounded-2xl flex items-center justify-center shadow-lg shadow-blue-500/20">
                  <Bot className="w-7 h-7" />
                </div>
                <div>
                  <h3 className="font-black text-lg tracking-tight">Kheja_Link AI</h3>
                  <div className="flex items-center gap-1.5">
                    <span className="w-2 h-2 bg-emerald-500 rounded-full animate-pulse" />
                    <span className="text-[10px] uppercase font-black tracking-widest text-zinc-400">
                      Always Online
                    </span>
                  </div>
                </div>
              </div>
              <button
                onClick={() => setIsOpen(false)}
                aria-label="Close the assistant"
                className="relative w-10 h-10 bg-white/10 hover:bg-white/20 rounded-full flex items-center justify-center transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Chat Messages */}
            <div
              ref={scrollRef}
              className="flex-1 overflow-y-auto p-6 space-y-6 scrollbar-hide bg-zinc-50 dark:bg-zinc-900/50"
            >
              {messages.map((msg) => (
                <motion.div
                  key={msg.id}
                  initial={{ opacity: 0, y: 10, scale: 0.95 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  className="space-y-3"
                >
                  <div
                    className={`flex items-start gap-3 ${msg.role === "user" ? "flex-row-reverse" : ""}`}
                  >
                    <div
                      className={`w-8 h-8 rounded-xl flex items-center justify-center shrink-0 ${
                        msg.role === "user"
                          ? "bg-zinc-900 dark:bg-white text-white dark:text-zinc-900"
                          : "bg-blue-600 text-white"
                      }`}
                    >
                      {msg.role === "user" ? <User className="w-4 h-4" /> : <Sparkles className="w-4 h-4" />}
                    </div>
                    <div
                      className={`max-w-[80%] p-4 rounded-3xl text-sm font-medium leading-relaxed shadow-sm ${
                        msg.role === "user"
                          ? "bg-zinc-900 dark:bg-white text-white dark:text-zinc-900 rounded-tr-none"
                          : "bg-white dark:bg-zinc-800 text-zinc-900 dark:text-white rounded-tl-none border border-zinc-200 dark:border-zinc-700"
                      }`}
                    >
                      {msg.content}
                    </div>
                  </div>

                  {/* Real listings, straight from the database */}
                  {msg.properties && msg.properties.length > 0 && (
                    <div className="pl-11 space-y-2">
                      {msg.properties.map((property) => (
                        <Link
                          key={property.id}
                          href={`/properties/${property.slug}`}
                          onClick={() => setIsOpen(false)}
                          className="flex items-center gap-3 p-2 bg-white dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-2xl hover:border-blue-500 transition-colors group"
                        >
                          <span className="relative w-14 h-14 rounded-xl overflow-hidden bg-zinc-100 dark:bg-zinc-700 shrink-0">
                            {property.image && (
                              <Image
                                src={property.image}
                                alt=""
                                fill
                                sizes="56px"
                                className="object-cover"
                              />
                            )}
                          </span>
                          <span className="min-w-0 flex-1">
                            <span className="block text-xs font-black text-zinc-900 dark:text-white truncate">
                              {property.title}
                            </span>
                            <span className="block text-[11px] font-bold text-blue-600">
                              {property.price}
                            </span>
                            <span className="block text-[10px] font-bold uppercase tracking-wider text-zinc-400 truncate">
                              {property.location}
                            </span>
                          </span>
                          <ArrowUpRight className="w-4 h-4 text-zinc-300 group-hover:text-blue-600 transition-colors shrink-0" />
                        </Link>
                      ))}
                      {msg.searchHref && (
                        <Link
                          href={msg.searchHref}
                          onClick={() => setIsOpen(false)}
                          className="block text-center text-[11px] font-black uppercase tracking-widest text-blue-600 hover:text-blue-700 py-2"
                        >
                          See all matches
                        </Link>
                      )}
                    </div>
                  )}
                </motion.div>
              ))}

              {/* Starter prompts, shown until the first question */}
              {messages.length === 1 && !isTyping && (
                <div className="pl-11 flex flex-wrap gap-2">
                  {SUGGESTIONS.map((suggestion) => (
                    <button
                      key={suggestion}
                      onClick={() => send(suggestion)}
                      className="px-3 py-2 bg-white dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 rounded-full text-[11px] font-bold text-zinc-600 dark:text-zinc-300 hover:border-blue-500 hover:text-blue-600 transition-colors"
                    >
                      {suggestion}
                    </button>
                  ))}
                </div>
              )}

              {isTyping && (
                <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex items-start gap-3">
                  <div className="w-8 h-8 bg-blue-600 rounded-xl flex items-center justify-center text-white">
                    <Sparkles className="w-4 h-4" />
                  </div>
                  <div className="bg-white dark:bg-zinc-800 p-4 rounded-3xl rounded-tl-none border border-zinc-200 dark:border-zinc-700">
                    <div className="flex gap-1">
                      <span className="w-1.5 h-1.5 bg-zinc-300 dark:bg-zinc-600 rounded-full animate-bounce" />
                      <span className="w-1.5 h-1.5 bg-zinc-300 dark:bg-zinc-600 rounded-full animate-bounce [animation-delay:0.2s]" />
                      <span className="w-1.5 h-1.5 bg-zinc-300 dark:bg-zinc-600 rounded-full animate-bounce [animation-delay:0.4s]" />
                    </div>
                  </div>
                </motion.div>
              )}
            </div>

            {/* Input Area */}
            <form
              onSubmit={(event) => {
                event.preventDefault();
                void send(inputValue);
              }}
              className="p-6 bg-white dark:bg-zinc-900 border-t border-zinc-100 dark:border-zinc-800 shrink-0"
            >
              <div className="relative">
                <input
                  ref={inputRef}
                  type="text"
                  value={inputValue}
                  onChange={(event) => setInputValue(event.target.value)}
                  placeholder="Ask about Meru rentals..."
                  aria-label="Ask the Kheja_Link assistant"
                  className="w-full h-14 pl-6 pr-14 bg-zinc-100 dark:bg-zinc-800 border-none rounded-2xl focus:ring-2 focus:ring-blue-600 text-zinc-900 dark:text-white font-bold placeholder:text-zinc-500 outline-none"
                />
                <button
                  type="submit"
                  disabled={!inputValue.trim() || isTyping}
                  aria-label="Send"
                  className="absolute right-2 top-2 w-10 h-10 bg-blue-600 text-white rounded-xl flex items-center justify-center hover:scale-105 active:scale-95 transition-all disabled:opacity-50 disabled:scale-100"
                >
                  <Send className="w-5 h-5" />
                </button>
              </div>
              <p className="mt-4 text-[10px] text-center text-zinc-400 font-black uppercase tracking-widest">
                Searching live Kheja_Link listings
              </p>
            </form>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
