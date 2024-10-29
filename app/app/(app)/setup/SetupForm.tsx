"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useForm } from "react-hook-form";
import { z } from "zod";

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
import { toast } from "sonner";
import { useRouter } from "next/navigation";
import { createServer } from "@/lib/db";

const FormSchema = z.object({
  url: z.string().min(2, {
    message: "Url must be at least 2 characters.",
  }),
  apikey: z.string().min(2, {
    message: "Apikey must be at least 2 characters.",
  }),
  name: z.string().min(2, {
    message: "Name must be at least 2 characters.",
  }),
  adminId: z.string().min(2, {
    message: "Admin ID must be at least 2 characters.",
  }),
});

export function SetupForm() {
  const router = useRouter();
  const form = useForm<z.infer<typeof FormSchema>>({
    resolver: zodResolver(FormSchema),
    defaultValues: {
      apikey: "",
      url: "",
      name: "",
      adminId: "",
    },
  });

  async function onSubmit(data: z.infer<typeof FormSchema>) {
    console.log(data);
    try {
      await createServer(data.url, data.apikey, data.adminId, data.name);
      router.push("/dashboard");
      // You can add a success message or redirect the user here
    } catch (error) {
      console.error("Error saving API key:", error);
      toast.error("Error saving API key");
    }
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="w-2/3 space-y-6">
        <FormField
          control={form.control}
          name="name"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Jellyfin Name</FormLabel>
              <FormControl>
                <Input placeholder="Jellyfin" {...field} />
              </FormControl>
              <FormDescription>
                Enter the name of your Jellyfin server
              </FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
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
        <FormField
          control={form.control}
          name="adminId"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Jellyfin Admin ID</FormLabel>
              <FormControl>
                <Input placeholder="shadcn" {...field} />
              </FormControl>
              <FormDescription>
                An admin id from Jellyfin with access to all libraries
              </FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        <Button type="submit">Submit</Button>
      </form>
    </Form>
  );
}
