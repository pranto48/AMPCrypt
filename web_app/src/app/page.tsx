import Navbar from "@/components/Navbar";
import { Shield, Lock, Cpu, Server, Key, ArrowUpRight } from "lucide-react";

export default function Home() {
  return (
    <div className="bg-[#0A0A0A] text-white min-h-screen relative overflow-hidden font-sans">
      <Navbar />

      {/* Decorative glow gradients */}
      <div className="absolute top-0 left-1/4 w-[500px] h-[500px] bg-[#00E5FF]/10 rounded-full filter blur-[120px] pointer-events-none" />
      <div className="absolute top-1/3 right-1/4 w-[600px] h-[600px] bg-blue-600/10 rounded-full filter blur-[150px] pointer-events-none" />

      {/* Hero Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-32 pb-24 relative z-10">
        <div className="text-center max-w-3xl mx-auto mt-16">
          <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-white/5 border border-white/10 text-xs font-semibold tracking-wider text-gray-400 uppercase mb-8 hover:bg-white/10 transition-colors cursor-pointer">
            <span className="flex h-2 w-2 rounded-full bg-[#00E5FF] animate-pulse" />
            Zero-Trust Encryption is Here
          </div>
          <h1 className="text-5xl sm:text-6xl font-extrabold tracking-tight leading-tight bg-clip-text text-transparent bg-gradient-to-r from-white via-gray-100 to-gray-500">
            Secure Your Data with <span className="text-[#00E5FF] shadow-[#00E5FF]/10 shadow-sm">AMPCrypt</span>
          </h1>
          <p className="mt-6 text-lg sm:text-xl text-gray-400 leading-relaxed">
            Enterprise-grade client-side encryption. Securely split secrets using Shamir's Secret Sharing, synchronise devices, and safeguard files without trusting any central server.
          </p>
          <div className="mt-10 flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="#download"
              className="px-8 py-4 bg-[#00E5FF] text-black font-bold rounded-xl shadow-lg shadow-cyan-500/20 hover:bg-[#00E5FF]/90 transition-all hover:scale-105 active:scale-95"
            >
              Get Started Free
            </a>
            <a
              href="#docs"
              className="px-8 py-4 bg-white/5 text-white font-semibold rounded-xl border border-white/10 hover:bg-white/10 transition-all hover:scale-105 active:scale-95 flex items-center justify-center gap-2"
            >
              Read Security whitepaper <ArrowUpRight className="w-4 h-4 text-gray-400" />
            </a>
          </div>
        </div>

        {/* Feature Grid */}
        <section className="mt-32 grid grid-cols-1 md:grid-cols-3 gap-8">
          <div className="bg-[#111]/40 border border-white/5 rounded-2xl p-8 hover:border-white/10 transition-all group hover:bg-[#111]/80">
            <div className="w-12 h-12 rounded-xl bg-white/5 flex items-center justify-center group-hover:bg-[#00E5FF]/10 transition-colors mb-6">
              <Lock className="w-6 h-6 text-gray-400 group-hover:text-[#00E5FF] transition-colors" />
            </div>
            <h3 className="text-xl font-bold mb-3 text-white group-hover:text-[#00E5FF] transition-colors">
              Zero-Knowledge Vaults
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed">
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
            <p className="text-gray-400 text-sm leading-relaxed">
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
            <p className="text-gray-400 text-sm leading-relaxed">
              Connect to custom WebDAV servers, standard cloud storage repositories, or our encrypted cloud sync.
            </p>
          </div>
        </section>
      </main>
    </div>
  );
}
