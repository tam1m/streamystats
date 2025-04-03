"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { z } from "zod";

import { PageTitle } from "@/components/PageTitle";
import { Spinner } from "@/components/Spinner";
import { Button } from "@/components/ui/button";
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { createServer } from "@/lib/db";
import { useRouter } from "nextjs-toploader/app";
import { useState } from "react";
import { toast } from "sonner";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
} from "@/components/ui/card";

const FormSchema = z.object({
  url: z.string().min(2, {
    message: "Url must be at least 2 characters.",
  }),
  apikey: z.string().min(2, {
    message: "Apikey must be at least 2 characters.",
  }),
});

export function SetupForm() {
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const form = useForm<z.infer<typeof FormSchema>>({
    resolver: zodResolver(FormSchema),
    defaultValues: {
      apikey: "",
      url: "",
    },
  });

  async function onSubmit(data: z.infer<typeof FormSchema>) {
    setLoading(true);
    try {
      const server = await createServer(data.url, data.apikey);

      if (!server || !server?.id) throw new Error("Server not created");

      router.push(`/servers/${server.id}/login`);
      // You can add a success message or redirect the user here
    } catch (error) {
      console.error("Error creating server:", error);
      toast.error("Error creating server");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex h-screen w-full items-center justify-center px-4">
      <Card className="mx-auto lg:min-w-[400px]">
        <CardHeader>
          <CardTitle className="text-2xl">Set up</CardTitle>
          <CardDescription>
            Setup Streamystats by adding a Jellyfin server
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
              <FormField
                control={form.control}
                name="url"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Jellyfin URL</FormLabel>
                    <FormControl>
                      <Input
                        placeholder="http://your-jellyfin-server:8096"
                        {...field}
                      />
                    </FormControl>
                    <FormDescription>
                      Enter the URL of your Jellyfin server
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="apikey"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Jellyfin Api Key</FormLabel>
                    <FormControl>
                      <Input placeholder="shadcn" {...field} />
                    </FormControl>
                    <FormDescription>
                      Get the api key from the admin dashboard in Jellyfin
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <Button type="submit" disabled={loading}>
                {loading ? <Spinner /> : "Create"}
              </Button>
            </form>
          </Form>
        </CardContent>
      </Card>
    </div>
  );
}
