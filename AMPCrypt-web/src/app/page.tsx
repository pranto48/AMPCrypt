/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

"use client";

import React, { useEffect, useState } from "react";
import { motion } from "framer-motion";
import Navbar from "@/components/Navbar";
import { Shield, Lock, Server, Key, ArrowUpRight, Code, Award, Download, CheckCircle, HelpCircle } from "lucide-react";

// AES-256 Block Matrix Animation component
function AES256Matrix() {
  const [matrix, setMatrix] = useState<string[][]>(() =>
    Array.from({ length: 4 }, () =>
      Array.from({ length: 4 }, () => Math.floor(Math.random() * 256).toString(16).toUpperCase().padStart(2, "0"))
    )
  );

  useEffect(() => {
    const interval = setInterval(() => {
      setMatrix((prev) =>
        prev.map((row) =>
          row.map((cell) => {
            if (Math.random() > 0.75) {
              return Math.floor(Math.random() * 256).toString(16).toUpperCase().padStart(2, "0");
            }
            return cell;
          })
        )
      );
    }, 400);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="relative w-full max-w-[420px] aspect-square p-6 liquid-glass-20 rounded-3xl shadow-[0_0_50px_rgba(0,240,255,0.15)] overflow-hidden group">
      <div className="absolute inset-0 border border-[#00F0FF]/20 rounded-3xl pointer-events-none group-hover:border-[#00F0FF]/60 transition-colors duration-500" />
      <div className="absolute -top-10 -left-10 w-40 h-40 bg-[#00F0FF]/15 rounded-full filter blur-3xl pointer-events-none" />

      <div className="grid grid-cols-4 grid-rows-4 gap-3.5 h-full w-full relative z-10 font-mono">
        {matrix.map((row, rIdx) =>
          row.map((cell, cIdx) => (
            <motion.div
              key={`${rIdx}-${cIdx}`}
              layout
              initial={{ opacity: 0.8 }}
              animate={{
                scale: [1, 1.02, 1],
                borderColor: ["rgba(0,240,255,0.1)", "rgba(0,240,255,0.4)", "rgba(0,240,255,0.1)"],
                boxShadow: [
                  "0 0 0px rgba(0,0,0,0)",
                  "0 0 12px rgba(0,240,255,0.25)",
                  "0 0 0px rgba(0,0,0,0)"
                ]
              }}
              transition={{
                duration: 2 + (rIdx + cIdx) * 0.3,
                repeat: Infinity,
                ease: "easeInOut"
              }}
              className="flex flex-col items-center justify-center rounded-xl bg-slate-900/40 border border-[#00F0FF]/20 relative group/cell cursor-default select-none backdrop-blur-sm"
            >
              <span className="text-xs text-gray-500 font-bold uppercase tracking-wider scale-75">
                B{rIdx * 4 + cIdx}
              </span>
              <motion.span
                key={cell}
                initial={{ opacity: 0.5, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                className="text-base sm:text-lg font-bold text-[#00F0FF] tracking-wide"
              >
                {cell}
              </motion.span>
              <div className="absolute inset-0 bg-[#00F0FF]/10 opacity-0 group-hover/cell:opacity-100 transition-opacity rounded-xl pointer-events-none" />
            </motion.div>
          ))
        )}
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <div className="bg-[#070D1E] text-white min-h-screen relative overflow-hidden font-sans">
      <Navbar />

      {/* 20% Liquid Ambient Lighting */}
      <div className="absolute top-0 left-1/4 w-[500px] h-[500px] bg-[#00F0FF]/10 rounded-full filter blur-[140px] pointer-events-none" />
      <div className="absolute top-1/3 right-1/4 w-[600px] h-[600px] bg-[#0072FF]/15 rounded-full filter blur-[160px] pointer-events-none" />

      {/* Hero Section */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-36 pb-20 relative z-10">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 items-center min-h-[calc(100vh-140px)]">
          
          {/* Headline and Copy */}
          <div className="lg:col-span-7 flex flex-col text-left space-y-8">
            <div className="inline-flex self-start items-center gap-2 px-4 py-2 rounded-full liquid-glass-20 text-xs font-semibold tracking-wider text-[#00F0FF] uppercase cursor-pointer font-mono">
              <span className="flex h-2 w-2 rounded-full bg-[#00F0FF] animate-pulse" />
              AES-256 20% Liquid Glass Security
            </div>
            
            <h1 className="text-4xl sm:text-6xl font-extrabold tracking-tight leading-tight bg-clip-text text-transparent bg-gradient-to-r from-white via-cyan-100 to-sky-400">
              Your Keys. <br />
              Your Storage. <br />
              <span className="text-[#00F0FF] drop-shadow-[0_0_20px_rgba(0,240,255,0.4)]">Absolute Sovereignty.</span>
            </h1>
            
            <p className="max-w-2xl text-base sm:text-lg text-gray-300 leading-relaxed font-mono">
              AMPCrypt is a zero-trust cryptographic client with a 20% translucent liquid glass design. Secure local files and sync vaults across multiple storage backends with absolute privacy.
            </p>

            {/* Installer CTAs */}
            <div className="flex flex-wrap gap-4 pt-2">
              <a
                href="/AMPCrypt-Setup.exe"
                download="AMPCrypt-Setup.exe"
                className="px-7 py-3.5 bg-gradient-to-r from-[#0072FF] to-[#00F0FF] text-white font-bold rounded-xl shadow-lg shadow-cyan-500/25 hover:shadow-cyan-500/40 transition-all hover:scale-[1.03] active:scale-95 flex items-center gap-2.5 text-sm"
              >
                <Download className="w-4 h-4" /> Download Windows Setup (.exe)
              </a>
              <a
                href="/AMPCrypt.msi"
                download="AMPCrypt.msi"
                className="px-6 py-3.5 liquid-glass-20 text-white font-semibold rounded-xl hover:bg-slate-800/40 transition-all hover:scale-[1.03] active:scale-95 flex items-center gap-2 text-sm"
              >
                Download MSI Installer
              </a>
              <a
                href="/ampcrypt.msix"
                download="ampcrypt.msix"
                className="px-6 py-3.5 liquid-glass-20 text-cyan-300 font-semibold rounded-xl hover:bg-slate-800/40 transition-all hover:scale-[1.03] active:scale-95 flex items-center gap-2 text-sm"
              >
                MSIX Package (.msix)
              </a>
            </div>

            {/* MSIX Certificate Trust Tip Box */}
            <div className="p-4 rounded-xl liquid-glass-20 border border-[#00F0FF]/30 text-xs text-cyan-100 flex items-start gap-3">
              <CheckCircle className="w-5 h-5 text-[#00F0FF] shrink-0 mt-0.5" />
              <div>
                <span className="font-bold text-white">Certificate Verification Tip (0x800B010A):</span> For MSIX double-click installation, run <code className="bg-slate-950/60 px-1.5 py-0.5 rounded text-[#00F0FF]">Install-AMPCrypt-MSIX.bat</code> included in the package to trust the publisher certificate automatically, or simply use <code className="bg-slate-950/60 px-1.5 py-0.5 rounded text-[#00F0FF]">AMPCrypt-Setup.exe</code> for instant 1-click setup.
              </div>
            </div>

            {/* Trust Badges */}
            <div className="pt-6 border-t border-white/10 flex flex-wrap gap-6 items-center">
              <div className="flex items-center gap-2.5 px-4 py-2 rounded-xl liquid-glass-20 text-gray-300 cursor-default">
                <Code className="w-4 h-4 text-[#00F0FF]" />
                <span className="text-xs font-semibold tracking-wider uppercase font-mono">Open Source</span>
              </div>
              
              <div className="flex items-center gap-2.5 px-4 py-2 rounded-xl liquid-glass-20 text-gray-300 cursor-default">
                <Lock className="w-4 h-4 text-[#00F0FF]" />
                <span className="text-xs font-semibold tracking-wider uppercase font-mono">Zero-Knowledge</span>
              </div>

              <div className="flex items-center gap-2.5 px-4 py-2 rounded-xl liquid-glass-20 text-gray-300 cursor-default">
                <Award className="w-4 h-4 text-[#00F0FF]" />
                <span className="text-xs font-semibold tracking-wider uppercase font-mono">Powered by IT Support BD</span>
              </div>
            </div>
          </div>

          {/* Graphical/Animation Pane */}
          <div className="lg:col-span-5 flex justify-center lg:justify-end">
            <AES256Matrix />
          </div>

        </div>

        {/* Feature Grid with 20% Liquid Translucency */}
        <section className="mt-28 grid grid-cols-1 md:grid-cols-3 gap-8">
          <div className="liquid-glass-20 liquid-glass-hover rounded-2xl p-8 group">
            <div className="w-12 h-12 rounded-xl bg-[#00F0FF]/10 flex items-center justify-center group-hover:bg-[#00F0FF]/25 transition-colors mb-6 border border-[#00F0FF]/30">
              <Shield className="w-6 h-6 text-[#00F0FF]" />
            </div>
            <h3 className="text-xl font-bold mb-3 text-white group-hover:text-[#00F0FF] transition-colors">
              Zero-Knowledge Vaults
            </h3>
            <p className="text-gray-300 text-sm leading-relaxed font-mono">
              We never see your files or encryption keys. Everything is processed directly on your local device before storage.
            </p>
          </div>

          <div className="liquid-glass-20 liquid-glass-hover rounded-2xl p-8 group">
            <div className="w-12 h-12 rounded-xl bg-[#00F0FF]/10 flex items-center justify-center group-hover:bg-[#00F0FF]/25 transition-colors mb-6 border border-[#00F0FF]/30">
              <Key className="w-6 h-6 text-[#00F0FF]" />
            </div>
            <h3 className="text-xl font-bold mb-3 text-white group-hover:text-[#00F0FF] transition-colors">
              Multi-Share Key Splitting
            </h3>
            <p className="text-gray-300 text-sm leading-relaxed font-mono">
              Split master vault recovery keys using SLIP-39 cryptography. Re-combine key shares securely when authenticating.
            </p>
          </div>

          <div className="liquid-glass-20 liquid-glass-hover rounded-2xl p-8 group">
            <div className="w-12 h-12 rounded-xl bg-[#00F0FF]/10 flex items-center justify-center group-hover:bg-[#00F0FF]/25 transition-colors mb-6 border border-[#00F0FF]/30">
              <Server className="w-6 h-6 text-[#00F0FF]" />
            </div>
            <h3 className="text-xl font-bold mb-3 text-white group-hover:text-[#00F0FF] transition-colors">
              Multi-Backend Storage
            </h3>
            <p className="text-gray-300 text-sm leading-relaxed font-mono">
              Connect to custom WebDAV servers, standard cloud storage repositories, or encrypted local drives seamlessly.
            </p>
          </div>
        </section>
      </main>
    </div>
  );
}
