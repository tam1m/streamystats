import { ItemDetails } from "@/components/ItemDetails";
import { getItemStatistics } from "@/lib/db";

export default async function ItemDetailsPage({
  params,
}: {
  params: Promise<{ id: string; itemId: string }>;
}) {
  const { id, itemId } = await params;

  const data = await getItemStatistics(id, itemId);

  if (!data) {
    return <div>Item not found</div>;
  }

  return (
    <div>
      <ItemDetails item={data.item} statistics={data.statistics} />
    </div>
  );
}
