import React, { useState } from "react";
import { View, Text, Pressable, ActivityIndicator } from "react-native";
import { router, useLocalSearchParams } from "expo-router";
import { LinearGradient } from "expo-linear-gradient";
import Animated, { FadeInDown } from "react-native-reanimated";
import { OtpInput } from "react-native-otp-entry";
import { authClient } from "@/lib/auth/auth-client";
import { useInvalidateSession } from "@/lib/auth/use-session";
import { ArrowLeft, ShieldCheck } from "lucide-react-native";

export default function VerifyOTP() {
  const { email } = useLocalSearchParams<{ email: string }>();
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const invalidateSession = useInvalidateSession();

  const handleVerifyOTP = async (otp: string) => {
    setLoading(true);
    setError(null);
    try {
      const result = await authClient.signIn.emailOtp({
        email: email?.trim() ?? "",
        otp,
      });
      if (result.error) {
        setError(result.error.message || "Invalid verification code");
        setLoading(false);
      } else {
        await invalidateSession();
      }
    } catch {
      setError("Network error. Please try again.");
      setLoading(false);
    }
  };

  const handleResend = async () => {
    if (!email) return;
    await authClient.emailOtp.sendVerificationOtp({
      email: email.trim(),
      type: "sign-in",
    });
    setError(null);
  };

  return (
    <LinearGradient colors={["#0A0F1E", "#111827", "#0A0F1E"]} style={{ flex: 1 }}>
      <View style={{ flex: 1, paddingHorizontal: 24, paddingTop: 60 }}>
        <Pressable onPress={() => router.back()} style={{ marginBottom: 32 }} testID="back-button">
          <ArrowLeft size={24} color="#9CA3AF" />
        </Pressable>

        <Animated.View entering={FadeInDown.delay(100).springify()} style={{ marginBottom: 32 }}>
          <View style={{
            width: 64, height: 64, borderRadius: 18, backgroundColor: "#1C2438",
            borderWidth: 1, borderColor: "#3B82F620", alignItems: "center",
            justifyContent: "center", marginBottom: 20,
          }}>
            <ShieldCheck size={30} color="#3B82F6" />
          </View>
          <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 32, color: "#FFFFFF" }}>
            Verify your{"\n"}identity
          </Text>
          <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 16, color: "#9CA3AF", marginTop: 8, lineHeight: 24 }}>
            Enter the 6-digit code sent to{"\n"}
            <Text style={{ color: "#3B82F6" }}>{email}</Text>
          </Text>
        </Animated.View>

        <Animated.View entering={FadeInDown.delay(200).springify()} style={{ marginBottom: 24 }}>
          <View testID="otp-input">
            <OtpInput
              numberOfDigits={6}
              onFilled={handleVerifyOTP}
              type="numeric"
              disabled={loading}
              theme={{
                containerStyle: { gap: 10 },
                pinCodeContainerStyle: {
                  backgroundColor: "#1C2438", borderColor: "#2D3748",
                  borderRadius: 14, width: 48, height: 56,
                },
                focusedPinCodeContainerStyle: { borderColor: "#3B82F6" },
                pinCodeTextStyle: { fontFamily: "DMSans_700Bold", fontSize: 22, color: "#FFFFFF" },
              }}
            />
          </View>
          {!!error && (
            <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#EF4444", marginTop: 12, textAlign: "center" }}>
              {error}
            </Text>
          )}
        </Animated.View>

        {!!loading && (
          <Animated.View entering={FadeInDown} style={{ alignItems: "center", marginBottom: 16 }}>
            <ActivityIndicator color="#3B82F6" size="large" />
            <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#6B7280", marginTop: 8 }}>
              Signing you in...
            </Text>
          </Animated.View>
        )}

        <Animated.View entering={FadeInDown.delay(300).springify()} style={{ alignItems: "center" }}>
          <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#6B7280" }}>
            Didn't receive the code?
          </Text>
          <Pressable onPress={handleResend} style={{ marginTop: 4 }} testID="resend-otp-button">
            <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 14, color: "#3B82F6" }}>
              Resend code
            </Text>
          </Pressable>
        </Animated.View>
      </View>
    </LinearGradient>
  );
}
