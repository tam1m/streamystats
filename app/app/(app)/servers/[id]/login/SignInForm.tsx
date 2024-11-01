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
import { login, Server } from "@/lib/db";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { tokenAtom } from "@/lib/atoms/tokenAtom";
import { useAtom } from "jotai/react";
import { useState } from "react";
import { Loader2 } from "lucide-react";
import { PageTitle } from "@/components/PageTitle";
import { Spinner } from "@/components/Spinner";

const FormSchema = z.object({
  username: z.string(),
  password: z.string().optional(),
});

interface Props {
  server: Server;
}

export const SignInForm: React.FC<Props> = ({ server }) => {
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const form = useForm<z.infer<typeof FormSchema>>({
    resolver: zodResolver(FormSchema),
    defaultValues: {
      username: "",
      password: "",
    },
  });

  async function onSubmit(data: z.infer<typeof FormSchema>) {
    setLoading(true);
    try {
      await login({
        serverId: server.id,
        username: data.username,
        password: data.password,
      });
      router.push(`/servers/${server.id}/dashboard`);
      toast.success("Logged in successfully");
    } catch (error) {
      console.error("Error logging in:", error);
      toast.error("Error logging in");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="w-full space-y-6">
        <PageTitle title="Sign In" subtitle="Sign in to your Jellyfin server" />
        <FormField
          control={form.control}
          name="username"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Username</FormLabel>
              <FormControl>
                <Input
                  placeholder="Enter your Jellyfin username"
                  {...field}
                  autoComplete="username"
                />
              </FormControl>
              <FormDescription>Enter your Jellyfin username</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
        <FormField
          control={form.control}
          name="password"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Password</FormLabel>
              <FormControl>
                <Input
                  type="password"
                  placeholder="Enter your Jellyfin password"
                  {...field}
                  autoComplete="current-password"
                />
              </FormControl>
              <FormDescription>Jellyfin password</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />

        <Button type="submit">{loading ? <Spinner /> : "Sign In"}</Button>
      </form>
    </Form>
  );
};
