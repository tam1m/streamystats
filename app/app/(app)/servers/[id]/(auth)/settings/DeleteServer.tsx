"use client";

import { Spinner } from "@/components/Spinner";
import { Button } from "@/components/ui/button";
import { deleteServer, Server } from "@/lib/db";
import { Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";

interface Props {
  server: Server;
}

export const DeleteServer: React.FC<Props> = ({ server }) => {
  const [loading, setLoading] = useState<boolean>(false);
  const router = useRouter();
  return (
    <div className="border p-4 rounded-lg">
      <Button
        variant={"destructive"}
        onClick={async () => {
          setLoading(true);
          try {
            await deleteServer(server.id);
            router.push("/");
          } catch (error) {
            toast.error("Something went wrong");
            console.log(error);
          } finally {
            setLoading(false);
          }
        }}
      >
        {loading ? <Spinner /> : "Delete Server"}
      </Button>
    </div>
  );
};
