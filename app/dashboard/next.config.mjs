/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Catalog JSON lives in the sibling app/metadata dir (outside the Next root); allow reading it.
  outputFileTracingIncludes: {
    "/**": ["../metadata/**/*.json"],
  },
};

export default nextConfig;
