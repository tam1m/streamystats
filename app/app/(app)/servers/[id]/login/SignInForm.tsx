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
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

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
      toast.success("Logged in successfully");
      router.push(`/servers/${server.id}/dashboard`);
    } catch (error) {
      toast.error("Error logging in");
      console.error("Error logging in:", error);
      setLoading(false);
    }
  }

  return (
    <div className="flex h-screen w-full items-center justify-center px-4">
      <Card className="mx-auto lg:min-w-[400px]">
        <CardHeader>
          <CardTitle className="text-2xl">Log in</CardTitle>
          <CardDescription>
            Log in to Streamystats by using your Jellyfin account
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form {...form}>
            <form
              onSubmit={form.handleSubmit(onSubmit)}
              className="w-full space-y-6"
            >
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
                    <FormDescription>
                      Enter your Jellyfin username
                    </FormDescription>
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
        </CardContent>
      </Card>
    </div>
  );
};
