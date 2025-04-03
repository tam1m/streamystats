import { useRouter, useSearchParams } from "next/navigation";

/**
 * Hook for managing query parameters in the URL
 * @returns Function to update query parameters
 */
export function useQueryParams() {
  const router = useRouter();
  const searchParams = useSearchParams();

  /**
   * Updates URL query parameters
   * @param params Record of key-value pairs to update in the URL
   * @param options Additional options like scroll behavior
   */
  const updateQueryParams = (
    params: Record<string, string | null>,
    options: { scroll?: boolean } = { scroll: false }
  ) => {
    const newSearchParams = new URLSearchParams(searchParams.toString());

    // Update or remove each parameter
    Object.entries(params).forEach(([key, value]) => {
      if (value === null) {
        newSearchParams.delete(key);
      } else {
        newSearchParams.set(key, value);
      }
    });

    router.push(`?${newSearchParams.toString()}`, { scroll: options.scroll });
  };

  return { updateQueryParams };
}
