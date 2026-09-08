/** @type {import('next').NextConfig} */
const nextConfig = {
  async headers() {
    return [
      {
        source: "/app/vault/:path*",
        headers: [
          {
            key: "Content-Security-Policy",
            value: [
              "default-src 'self';",
              "script-src 'self' 'unsafe-eval';",
              "style-src 'self' 'unsafe-inline';",
              "connect-src 'self' wss: https:;",
              "worker-src 'self' blob:;",
              "frame-ancestors 'none';",
              "object-src 'none';",
              "img-src 'self' data:;",
            ].join(" "),
          },
          {
            key: "X-Frame-Options",
            value: "DENY",
          },
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
        ],
      },
    ];
  },
};

export default nextConfig;
