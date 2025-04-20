export const VersionBadge = () => (
  <div className="fixed bottom-2 right-2 bg-gray-800 text-white text-xs px-2 py-1 rounded">
    <code suppressHydrationWarning>
      {process.env.NEXT_PUBLIC_VERSION ?? "edge"}
    </code>
  </div>
);
