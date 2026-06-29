"use client";

import React, { useEffect, useState } from "react";
import { motion } from "framer-motion";
import Navbar from "@/components/Navbar";
import { Shield, Lock, Server, Key, ArrowUpRight, Code, Award } from "lucide-react";

// AES-256 Block Matrix Animation component
function AES256Matrix() {
  const [matrix, setMatrix] = useState<string[][]>(() =>
    Array.from({ length: 4 }, () =>
      Array.from({ length: 4 }, () => Math.floor(Math.random() * 256).toString(16).toUpperCase().padStart(2, "0"))
    )
  );

  useEffect(() => {
    const interval = setInterval(() => {
      // Periodically update random cells to simulate AES state updates (SubBytes, ShiftRows)
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
    <div className="relative w-full max-w-[420px] aspect-square p-6 bg-[#0E0E0E]/60 rounded-3xl border border-white/5 shadow-[0_0_50px_rgba(0,0,0,0.8)] backdrop-blur-md overflow-hidden group">
      {/* Dynamic tech border lines */}
      <div className="absolute inset-0 border border-white/10 rounded-3xl pointer-events-none group-hover:border-[#00E5FF]/20 transition-colors duration-500" />
      <div className="absolute -top-10 -left-10 w-40 h-40 bg-[#00E5FF]/10 rounded-full filter blur-3xl pointer-events-none" />

      {/* Grid container */}
      <div className="grid grid-cols-4 grid-rows-4 gap-3.5 h-full w-full relative z-10 font-mono">
        {matrix.map((row, rIdx) =>
          row.map((cell, cIdx) => (
            <motion.div
              key={`${rIdx}-${cIdx}`}
              layout
              initial={{ opacity: 0.8 }}
              animate={{
                scale: [1, 1.02, 1],
                borderColor: ["rgba(255,255,255,0.05)", "rgba(0,229,255,0.3)", "rgba(255,255,255,0.05)"],
                boxShadow: [
                  "0 0 0px rgba(0,0,0,0)",
                  "0 0 10px rgba(0,229,255,0.15)",
                  "0 0 0px rgba(0,0,0,0)"
                ]
              }}
              transition={{
                duration: 2 + (rIdx + cIdx) * 0.3,
                repeat: Infinity,
                ease: "easeInOut"
              }}
              className="flex flex-col items-center justify-center rounded-xl bg-[#141414]/90 border border-white/5 relative group/cell cursor-default select-none"
            >
              <span className="text-xs text-gray-600 font-bold uppercase tracking-wider scale-75">
                B{rIdx * 4 + cIdx}
              </span>
              <motion.span
                key={cell}
                initial={{ opacity: 0.5, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                className="text-base sm:text-lg font-bold text-[#00E5FF] tracking-wide"
              >
                {cell}
              </motion.span>
              <div className="absolute inset-0 bg-[#00E5FF]/5 opacity-0 group-hover/cell:opacity-100 transition-opacity rounded-xl pointer-events-none" />
            </motion.div>
          ))
        )}
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <div className="bg-[#0A0A0A] text-white min-h-screen relative overflow-hidden font-sans">
      <Navbar />

      {/* Background ambient animations */}
      <div className="absolute top-0 left-1/4 w-[500px] h-[500px] bg-[#00E5FF]/10 rounded-full filter blur-[120px] pointer-events-none" />
      <div className="absolute top-1/3 right-1/4 w-[600px] h-[600px] bg-blue-600/10 rounded-full filter blur-[150px] pointer-events-none" />

      {/* Hero Section */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-36 pb-20 relative z-10">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 items-center min-h-[calc(100vh-140px)]">
          
          {/* Headline and Copy (Left column) */}
          <div className="lg:col-span-7 flex flex-col text-left space-y-8">
            <div className="inline-flex self-start items-center gap-2 px-3.5 py-1.5 rounded-full bg-white/5 border border-white/10 text-xs font-semibold tracking-wider text-gray-400 uppercase hover:bg-white/10 transition-colors cursor-pointer font-mono">
              <span className="flex h-2 w-2 rounded-full bg-[#00E5FF] animate-pulse" />
              AES-256 Block Cipher System
            </div>
            
            <h1 className="text-4xl sm:text-6xl font-extrabold tracking-tight leading-tight bg-clip-text text-transparent bg-gradient-to-r from-white via-gray-100 to-gray-500">
              Your Keys. <br />
              Your Storage. <br />
              <span className="text-[#00E5FF]">Absolute Sovereignty.</span>
            </h1>
            
            <p className="max-w-2xl text-base sm:text-lg text-gray-400 leading-relaxed font-mono">
              AMPCrypt is a zero-trust cryptographic client that secures local files and synchronizes vaults across multiple storage backends. We do not run storage databases; you retain absolute ownership.
            </p>

            {/* CTAs */}
            <div className="flex flex-col sm:flex-row gap-4 pt-2">
              <a
                href="/Ampcrypt-Installer.exe"
                download="Ampcrypt-Installer.exe"
                className="px-8 py-4 bg-[#00E5FF] text-black font-bold rounded-xl shadow-lg shadow-cyan-500/20 hover:bg-[#00E5FF]/90 transition-all hover:scale-[1.03] active:scale-95 text-center"
              >
                Download Client
              </a>
              <a
                href="#docs"
                className="px-8 py-4 bg-white/5 text-white font-semibold rounded-xl border border-white/10 hover:bg-white/10 transition-all hover:scale-[1.03] active:scale-95 flex items-center justify-center gap-2"
              >
                Security Whitepaper <ArrowUpRight className="w-4 h-4 text-gray-400" />
              </a>
            </div>

            {/* Trust Badges */}
            <div className="pt-8 border-t border-white/5 flex flex-wrap gap-6 items-center">
              <div className="flex items-center gap-2.5 px-4 py-2 rounded-xl bg-white/[0.02] border border-white/5 text-gray-400 hover:border-white/10 hover:text-white transition-colors cursor-default">
                <Code className="w-4 h-4 text-[#00E5FF]" />
                <span className="text-xs font-semibold tracking-wider uppercase font-mono">Open Source</span>
              </div>
              
              <div className="flex items-center gap-2.5 px-4 py-2 rounded-xl bg-white/[0.02] border border-white/5 text-gray-400 hover:border-white/10 hover:text-white transition-colors cursor-default">
                <Lock className="w-4 h-4 text-[#00E5FF]" />
                <span className="text-xs font-semibold tracking-wider uppercase font-mono">Zero-Knowledge</span>
              </div>

              <div className="flex items-center gap-2.5 px-4 py-2 rounded-xl bg-white/[0.02] border border-white/5 text-gray-400 hover:border-white/10 hover:text-white transition-colors cursor-default">
                <Award className="w-4 h-4 text-[#00E5FF]" />
                <span className="text-xs font-semibold tracking-wider uppercase font-mono">Powered by IT Support BD</span>
              </div>
            </div>
          </div>

          {/* Graphical/Animation Pane (Right column) */}
          <div className="lg:col-span-5 flex justify-center lg:justify-end">
            <AES256Matrix />
          </div>

        </div>

        {/* Feature Grid */}
        <section className="mt-32 grid grid-cols-1 md:grid-cols-3 gap-8">
          <div className="bg-[#111]/40 border border-white/5 rounded-2xl p-8 hover:border-white/10 transition-all group hover:bg-[#111]/80">
            <div className="w-12 h-12 rounded-xl bg-white/5 flex items-center justify-center group-hover:bg-[#00E5FF]/10 transition-colors mb-6">
              <Shield className="w-6 h-6 text-gray-400 group-hover:text-[#00E5FF] transition-colors" />
            </div>
            <h3 className="text-xl font-bold mb-3 text-white group-hover:text-[#00E5FF] transition-colors">
              Zero-Knowledge Vaults
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed font-mono">
              We never see your files or encryption keys. Everything is processed directly on your local device before uploading.
            </p>
          </div>

          <div className="bg-[#111]/40 border border-white/5 rounded-2xl p-8 hover:border-white/10 transition-all group hover:bg-[#111]/80">
            <div className="w-12 h-12 rounded-xl bg-white/5 flex items-center justify-center group-hover:bg-[#00E5FF]/10 transition-colors mb-6">
              <Key className="w-6 h-6 text-gray-400 group-hover:text-[#00E5FF] transition-colors" />
            </div>
            <h3 className="text-xl font-bold mb-3 text-white group-hover:text-[#00E5FF] transition-colors">
              Multi-Share Key Splitting
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed font-mono">
              Split master vault recovery keys using advanced cryptography. Re-combine key shares only when authenticating.
            </p>
          </div>

          <div className="bg-[#111]/40 border border-white/5 rounded-2xl p-8 hover:border-white/10 transition-all group hover:bg-[#111]/80">
            <div className="w-12 h-12 rounded-xl bg-white/5 flex items-center justify-center group-hover:bg-[#00E5FF]/10 transition-colors mb-6">
              <Server className="w-6 h-6 text-gray-400 group-hover:text-[#00E5FF] transition-colors" />
            </div>
            <h3 className="text-xl font-bold mb-3 text-white group-hover:text-[#00E5FF] transition-colors">
              Multi-Backend Storage
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed font-mono">
              Connect to custom WebDAV servers, standard cloud storage repositories, or our encrypted cloud sync.
            </p>
          </div>
        </section>
      </main>
    </div>
  );
}
