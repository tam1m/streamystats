export const VersionBadge = () => (
  <code suppressHydrationWarning>
    {process.env.NEXT_PUBLIC_VERSION ?? "edge"}
  </code>
);
