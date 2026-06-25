"use client";

import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Menu, X, ChevronDown, Monitor, Globe, Terminal, ArrowRight, Shield, ExternalLink } from "lucide-react";

interface ProductItem {
  name: string;
  description: string;
  icon: React.ComponentType<{ className?: string }>;
  href: string;
}

const products: ProductItem[] = [
  {
    name: "Desktop Sync",
    description: "Secure local folder vault sync with dynamic virtual drive mounting.",
    icon: Monitor,
    href: "#desktop",
  },
  {
    name: "Web App",
    description: "Access your encrypted files from any browser with zero-knowledge keys.",
    icon: Globe,
    href: "#web",
  },
  {
    name: "CLI Tools",
    description: "Integrate secure encryption directly into build scripts and terminal environments.",
    icon: Terminal,
    href: "#cli",
  },
];

export default function Navbar() {
  const [isOpen, setIsOpen] = useState(false);
  const [isProductsHovered, setIsProductsHovered] = useState(false);

  return (
    <nav className="fixed top-0 left-0 w-full z-50 bg-[#0A0A0A]/80 backdrop-blur-md border-b border-white/10 font-sans text-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-20">
          {/* Logo */}
          <div className="flex-shrink-0 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-gradient-to-tr from-cyan-500 to-blue-600 flex items-center justify-center shadow-lg shadow-cyan-500/20">
              <Shield className="w-6 h-6 text-white" />
            </div>
            <span className="text-xl font-bold tracking-wider bg-clip-text text-transparent bg-gradient-to-r from-white to-gray-400">
              AMP<span className="text-[#00E5FF]">Crypt</span>
            </span>
          </div>

          {/* Desktop Nav Links */}
          <div className="hidden md:flex items-center gap-8">
            <div
              className="relative py-6"
              onMouseEnter={() => setIsProductsHovered(true)}
              onMouseLeave={() => setIsProductsHovered(false)}
            >
              <button className="flex items-center gap-1.5 text-sm font-medium text-gray-300 hover:text-[#00E5FF] transition-colors focus:outline-none">
                Products
                <ChevronDown className={`w-4 h-4 transition-transform duration-200 ${isProductsHovered ? "rotate-180 text-[#00E5FF]" : ""}`} />
              </button>

              <AnimatePresence>
                {isProductsHovered && (
                  <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: 10 }}
                    transition={{ duration: 0.15 }}
                    className="absolute left-0 mt-2 w-[480px] bg-[#0A0A0A] border border-white/10 rounded-xl shadow-2xl p-6 grid grid-cols-2 gap-4"
                  >
                    <div className="col-span-2 text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
                      Available Platforms
                    </div>
                    {products.map((item) => {
                      const Icon = item.icon;
                      return (
                        <a
                          key={item.name}
                          href={item.href}
                          className="flex gap-4 p-3 rounded-lg hover:bg-white/5 transition-all group"
                        >
                          <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-white/5 flex items-center justify-center group-hover:bg-[#00E5FF]/10 transition-colors">
                            <Icon className="w-5 h-5 text-gray-400 group-hover:text-[#00E5FF] transition-colors" />
                          </div>
                          <div>
                            <div className="text-sm font-semibold text-white group-hover:text-[#00E5FF] transition-colors flex items-center gap-1">
                              {item.name}
                              <ExternalLink className="w-3.5 h-3.5 opacity-0 group-hover:opacity-100 transition-opacity" />
                            </div>
                            <p className="text-xs text-gray-400 mt-1 line-clamp-2">{item.description}</p>
                          </div>
                        </a>
                      );
                    })}
                    <div className="col-span-2 border-t border-white/5 pt-4 mt-2 flex justify-between items-center text-xs">
                      <span className="text-gray-500">Need custom integrations?</span>
                      <a href="#enterprise" className="text-[#00E5FF] hover:underline flex items-center gap-1 font-medium">
                        Contact Enterprise <ArrowRight className="w-3 h-3" />
                      </a>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>

            <a href="#features" className="text-sm font-medium text-gray-300 hover:text-[#00E5FF] transition-colors">
              Features
            </a>
            <a href="#enterprise" className="text-sm font-medium text-gray-300 hover:text-[#00E5FF] transition-colors">
              Enterprise
            </a>
            <a href="#support" className="text-sm font-medium text-gray-300 hover:text-[#00E5FF] transition-colors">
              Support
            </a>
          </div>

          {/* Download CTA Button */}
          <div className="hidden md:block">
            <a
              href="#download"
              className="relative inline-flex items-center justify-center px-6 py-2.5 text-sm font-bold text-black bg-[#00E5FF] rounded-lg overflow-hidden transition-all hover:bg-[#00E5FF]/90 active:scale-95 group shadow-[0_0_20px_rgba(0,229,255,0.3)] hover:shadow-[0_0_30px_rgba(0,229,255,0.5)]"
            >
              Download Free
            </a>
          </div>

          {/* Mobile hamburger menu */}
          <div className="md:hidden">
            <button
              onClick={() => setIsOpen(!isOpen)}
              className="p-2 rounded-md text-gray-400 hover:text-white focus:outline-none"
            >
              {isOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
      </div>

      {/* Mobile Menu Panel */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="md:hidden bg-[#0A0A0A] border-b border-white/10"
          >
            <div className="px-4 pt-2 pb-6 space-y-4">
              <div className="space-y-2">
                <div className="text-xs font-semibold text-gray-500 uppercase tracking-wider px-3">
                  Products
                </div>
                <div className="grid grid-cols-1 gap-2 pl-3">
                  {products.map((item) => {
                    const Icon = item.icon;
                    return (
                      <a
                        key={item.name}
                        href={item.href}
                        onClick={() => setIsOpen(false)}
                        className="flex items-center gap-3 p-2 rounded-lg hover:bg-white/5"
                      >
                        <Icon className="w-5 h-5 text-[#00E5FF]" />
                        <div>
                          <div className="text-sm font-medium text-white">{item.name}</div>
                          <div className="text-xs text-gray-400">{item.description}</div>
                        </div>
                      </a>
                    );
                  })}
                </div>
              </div>

              <div className="border-t border-white/5 pt-4 space-y-2">
                <a
                  href="#features"
                  onClick={() => setIsOpen(false)}
                  className="block px-3 py-2 rounded-md text-base font-medium text-gray-300 hover:text-white hover:bg-white/5"
                >
                  Features
                </a>
                <a
                  href="#enterprise"
                  onClick={() => setIsOpen(false)}
                  className="block px-3 py-2 rounded-md text-base font-medium text-gray-300 hover:text-white hover:bg-white/5"
                >
                  Enterprise
                </a>
                <a
                  href="#support"
                  onClick={() => setIsOpen(false)}
                  className="block px-3 py-2 rounded-md text-base font-medium text-gray-300 hover:text-white hover:bg-white/5"
                >
                  Support
                </a>
              </div>

              <div className="pt-4 px-3">
                <a
                  href="#download"
                  onClick={() => setIsOpen(false)}
                  className="block w-full text-center py-3 text-sm font-bold text-black bg-[#00E5FF] rounded-lg"
                >
                  Download Free
                </a>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
}
