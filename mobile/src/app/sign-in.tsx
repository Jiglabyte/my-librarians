import React, { useState } from "react";
import {
  View, Text, TextInput, Pressable, ActivityIndicator,
  KeyboardAvoidingView, Platform, ScrollView, Image,
} from "react-native";
import { router } from "expo-router";
import { LinearGradient } from "expo-linear-gradient";
import Animated, { FadeInDown } from "react-native-reanimated";
import { authClient } from "@/lib/auth/auth-client";
import { Building2, Mail, ArrowRight } from "lucide-react-native";

export default function SignIn() {
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSendOTP = async () => {
    if (!email.trim()) {
      setError("Please enter your email address");
      return;
    }
    if (!email.includes("@")) {
      setError("Please enter a valid email address");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const result = await authClient.emailOtp.sendVerificationOtp({
        email: email.trim().toLowerCase(),
        type: "sign-in",
      });
      if (result.error) {
        setError(result.error.message || "Failed to send verification code");
      } else {
        router.push({
          pathname: "/verify-otp",
          params: { email: email.trim().toLowerCase() },
        });
      }
    } catch {
      setError("Network error. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <LinearGradient colors={["#0A0F1E", "#111827", "#0A0F1E"]} style={{ flex: 1 }}>
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : "height"}
        style={{ flex: 1 }}
      >
        <ScrollView contentContainerStyle={{ flexGrow: 1 }} keyboardShouldPersistTaps="handled">
          <View style={{ flex: 1, paddingHorizontal: 24, paddingTop: 80 }}>
            {/* Logo section */}
            <Animated.View entering={FadeInDown.delay(100).springify()} style={{ alignItems: "center", marginBottom: 48 }}>
              <View
                style={{ width: 80, height: 80, borderRadius: 40, backgroundColor: "#1E3A5F", alignItems: "center", justifyContent: "center", marginBottom: 16 }}
              >
                <Building2 size={36} color="#3B82F6" />
              </View>
              <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 28, color: "#FFFFFF", letterSpacing: 0.5 }}>
                MTA Timesheet
              </Text>
              <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#6B7280", marginTop: 4 }}>
                MTA International
              </Text>
            </Animated.View>

            {/* Welcome text */}
            <Animated.View entering={FadeInDown.delay(200).springify()} style={{ marginBottom: 32 }}>
              <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 32, color: "#FFFFFF", lineHeight: 40 }}>
                Welcome back
              </Text>
              <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 16, color: "#9CA3AF", marginTop: 8, lineHeight: 24 }}>
                Enter your work email to receive a{"\n"}verification code
              </Text>
            </Animated.View>

            {/* Email input */}
            <Animated.View entering={FadeInDown.delay(300).springify()} style={{ marginBottom: 16 }}>
              <View style={{
                flexDirection: "row", alignItems: "center", backgroundColor: "#1C2438",
                borderRadius: 16, borderWidth: 1, borderColor: error ? "#EF4444" : "#2D3748",
                paddingHorizontal: 16, paddingVertical: 4,
              }}>
                <Mail size={20} color="#6B7280" style={{ marginRight: 12 }} />
                <TextInput
                  value={email}
                  onChangeText={(t) => { setEmail(t); setError(null); }}
                  placeholder="your.email@company.com"
                  placeholderTextColor="#4B5563"
                  keyboardType="email-address"
                  autoCapitalize="none"
                  autoCorrect={false}
                  returnKeyType="done"
                  onSubmitEditing={handleSendOTP}
                  testID="email-input"
                  style={{ flex: 1, fontFamily: "DMSans_400Regular", fontSize: 16, color: "#FFFFFF", paddingVertical: 18 }}
                />
              </View>
              {!!error && (
                <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#EF4444", marginTop: 8, marginLeft: 4 }}>
                  {error}
                </Text>
              )}
            </Animated.View>

            {/* Send OTP Button */}
            <Animated.View entering={FadeInDown.delay(400).springify()}>
              <Pressable
                onPress={handleSendOTP}
                disabled={loading}
                testID="send-otp-button"
                style={({ pressed }) => ({
                  backgroundColor: pressed ? "#2563EB" : "#3B82F6",
                  borderRadius: 16, paddingVertical: 18, flexDirection: "row",
                  alignItems: "center", justifyContent: "center", opacity: loading ? 0.7 : 1,
                  shadowColor: "#3B82F6", shadowOpacity: 0.4, shadowRadius: 16,
                  shadowOffset: { width: 0, height: 6 },
                })}
              >
                {loading ? (
                  <ActivityIndicator color="#FFFFFF" />
                ) : (
                  <>
                    <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 16, color: "#FFFFFF", marginRight: 8 }}>
                      Send verification code
                    </Text>
                    <ArrowRight size={18} color="#FFFFFF" />
                  </>
                )}
              </Pressable>
            </Animated.View>

            {/* Bottom info */}
            <Animated.View entering={FadeInDown.delay(500).springify()} style={{ marginTop: 32, alignItems: "center" }}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                <Building2 size={14} color="#4B5563" />
                <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#4B5563" }}>
                  Secure employee portal
                </Text>
              </View>
            </Animated.View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </LinearGradient>
  );
}
