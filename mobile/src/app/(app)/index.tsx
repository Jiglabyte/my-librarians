import React, { useState, useEffect, useCallback, memo } from "react";
import {
  View, Text, Pressable, ScrollView, ActivityIndicator,
  RefreshControl, Modal, TextInput, Alert, Image,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { CameraView, useCameraPermissions } from "expo-camera";
import Animated, {
  useSharedValue, useAnimatedStyle, withSpring, withRepeat,
  withTiming, FadeInDown, FadeIn, interpolate,
} from "react-native-reanimated";
import * as Haptics from "expo-haptics";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api/api";
import { useSession } from "@/lib/auth/use-session";
import type { TimesheetEntry } from "@/lib/types";
import {
  CheckCircle, LogIn, LogOut, Smartphone, QrCode, Wifi,
  TrendingUp, Calendar, X, ScanLine, MapPin,
} from "lucide-react-native";

type ClockMethod = "manual" | "qr" | "nfc";

const METHODS: { id: ClockMethod; label: string; icon: React.ComponentType<{ size: number; color: string }> }[] = [
  { id: "manual", label: "Manual", icon: Smartphone },
  { id: "qr", label: "QR Code", icon: QrCode },
  { id: "nfc", label: "NFC Tag", icon: Wifi },
];

function getGreeting() {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
}

function formatElapsed(startTime: string): string {
  const [h, m] = startTime.split(":").map(Number);
  const now = new Date();
  const startMinutes = (h ?? 0) * 60 + (m ?? 0);
  const nowMinutes = now.getHours() * 60 + now.getMinutes();
  const diff = Math.max(0, nowMinutes - startMinutes);
  const hours = Math.floor(diff / 60);
  const minutes = diff % 60;
  return `${hours}h ${minutes}m`;
}

const LiveClock = memo(function LiveClock() {
  const [currentTime, setCurrentTime] = useState(new Date());
  useEffect(() => {
    const interval = setInterval(() => setCurrentTime(new Date()), 1000);
    return () => clearInterval(interval);
  }, []);
  const timeStr = currentTime.toLocaleTimeString("en-US", {
    hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: true,
  });
  const dateStr = currentTime.toLocaleDateString("en-US", {
    weekday: "long", month: "long", day: "numeric",
  });
  return (
    <View style={{ alignItems: "center", paddingVertical: 20 }}>
      <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 46, color: "#FFFFFF", letterSpacing: -1 }}>
        {timeStr}
      </Text>
      <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#6B7280", marginTop: 2 }}>
        {dateStr}
      </Text>
    </View>
  );
});

const ElapsedTimer = memo(function ElapsedTimer({ timeIn }: { timeIn: string }) {
  const [elapsed, setElapsed] = useState(() => formatElapsed(timeIn));
  useEffect(() => {
    const interval = setInterval(() => setElapsed(formatElapsed(timeIn)), 60000);
    return () => clearInterval(interval);
  }, [timeIn]);
  return (
    <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 22, color: "#3B82F6" }}>
      {elapsed}
    </Text>
  );
});

function QRScannerModal({ visible, onScanned, onClose }: {
  visible: boolean; onScanned: (data: string) => void; onClose: () => void;
}) {
  const [permission, requestPermission] = useCameraPermissions();
  const [scanned, setScanned] = useState(false);

  useEffect(() => { if (visible) setScanned(false); }, [visible]);

  const handleBarcode = ({ data }: { data: string }) => {
    if (scanned) return;
    setScanned(true);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    onScanned(data);
  };

  return (
    <Modal visible={visible} animationType="slide">
      <View style={{ flex: 1, backgroundColor: "#000" }}>
        <SafeAreaView edges={["top"]}>
          <View style={{ flexDirection: "row", alignItems: "center", paddingHorizontal: 20, paddingVertical: 12 }}>
            <Pressable onPress={onClose} style={{ marginRight: 16, padding: 8 }}>
              <X size={24} color="#FFFFFF" />
            </Pressable>
            <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 20, color: "#FFFFFF" }}>
              Scan QR Code
            </Text>
          </View>
        </SafeAreaView>

        {!permission?.granted ? (
          <View style={{ flex: 1, alignItems: "center", justifyContent: "center", padding: 32 }}>
            <QrCode size={64} color="#3B82F6" style={{ marginBottom: 20 }} />
            <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 18, color: "#FFFFFF", textAlign: "center", marginBottom: 8 }}>
              Camera permission required
            </Text>
            <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#9CA3AF", textAlign: "center", marginBottom: 24 }}>
              We need camera access to scan the QR code at your worksite
            </Text>
            <Pressable onPress={requestPermission}
              style={{ backgroundColor: "#3B82F6", borderRadius: 14, paddingVertical: 16, paddingHorizontal: 32 }}>
              <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 16, color: "#FFFFFF" }}>Allow Camera</Text>
            </Pressable>
          </View>
        ) : (
          <View style={{ flex: 1, position: "relative" }}>
            <CameraView style={{ flex: 1 }} facing="back"
              barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
              onBarcodeScanned={scanned ? undefined : handleBarcode} />
            <View style={{ position: "absolute", inset: 0, alignItems: "center", justifyContent: "center" }}>
              <View style={{ width: 240, height: 240, position: "relative" }}>
                {[
                  { top: 0, left: 0, borderTopWidth: 3, borderLeftWidth: 3 },
                  { top: 0, right: 0, borderTopWidth: 3, borderRightWidth: 3 },
                  { bottom: 0, left: 0, borderBottomWidth: 3, borderLeftWidth: 3 },
                  { bottom: 0, right: 0, borderBottomWidth: 3, borderRightWidth: 3 },
                ].map((style, i) => (
                  <View key={i} style={{ position: "absolute", width: 40, height: 40, borderColor: "#3B82F6", ...style }} />
                ))}
                <View style={{ position: "absolute", top: "50%", left: 0, right: 0, height: 2, backgroundColor: "#3B82F660" }} />
              </View>
              <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#FFFFFF", marginTop: 24, opacity: 0.8 }}>
                {scanned ? "QR code detected!" : "Align the QR code within the frame"}
              </Text>
            </View>
          </View>
        )}
      </View>
    </Modal>
  );
}

function NFCScanModal({ visible, action, onConfirm, onClose }: {
  visible: boolean; action: "in" | "out"; onConfirm: () => void; onClose: () => void;
}) {
  const pulseAnim = useSharedValue(0);

  useEffect(() => {
    if (visible) {
      pulseAnim.value = withRepeat(withTiming(1, { duration: 1200 }), -1, true);
    }
    return () => { pulseAnim.value = 0; };
  }, [visible, pulseAnim]);

  const pulseStyle = useAnimatedStyle(() => ({
    opacity: interpolate(pulseAnim.value, [0, 1], [0.2, 0.6]),
    transform: [{ scale: interpolate(pulseAnim.value, [0, 1], [1, 1.4]) }],
  }));

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <View style={{ flex: 1, backgroundColor: "#000000CC", justifyContent: "flex-end" }}>
        <View style={{
          backgroundColor: "#111827", borderTopLeftRadius: 28, borderTopRightRadius: 28,
          padding: 32, alignItems: "center",
        }}>
          <View style={{ position: "relative", alignItems: "center", justifyContent: "center", marginBottom: 24 }}>
            <Animated.View style={[{
              width: 120, height: 120, borderRadius: 60,
              backgroundColor: "#3B82F6", position: "absolute",
            }, pulseStyle]} />
            <View style={{
              width: 80, height: 80, borderRadius: 40,
              backgroundColor: "#1E3A5F", alignItems: "center", justifyContent: "center",
              borderWidth: 2, borderColor: "#3B82F6",
            }}>
              <Wifi size={36} color="#3B82F6" />
            </View>
          </View>

          <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 24, color: "#FFFFFF", marginBottom: 8 }}>
            Tap Your NFC Tag
          </Text>
          <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#9CA3AF", textAlign: "center", lineHeight: 22, marginBottom: 8 }}>
            Hold your phone near the NFC tag at your worksite to clock {action === "in" ? "in" : "out"}.
          </Text>
          <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#6B7280", textAlign: "center", marginBottom: 28 }}>
            NFC tag not yet configured? Use "Confirm" to proceed manually while your admin sets it up.
          </Text>

          <View style={{ flexDirection: "row", gap: 12, width: "100%" }}>
            <Pressable onPress={onClose}
              style={{ flex: 1, backgroundColor: "#1C2438", borderRadius: 14, paddingVertical: 16, alignItems: "center" }}>
              <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#9CA3AF" }}>Cancel</Text>
            </Pressable>
            <Pressable
              onPress={() => { Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success); onConfirm(); }}
              style={{ flex: 2, backgroundColor: "#3B82F6", borderRadius: 14, paddingVertical: 16, alignItems: "center" }}>
              <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#FFFFFF" }}>
                Confirm Clock {action === "in" ? "In" : "Out"}
              </Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

export default function HomeScreen() {
  const { data: session } = useSession();
  const queryClient = useQueryClient();
  const [selectedMethod, setSelectedMethod] = useState<ClockMethod>("manual");
  const [showCommentModal, setShowCommentModal] = useState(false);
  const [showQRScanner, setShowQRScanner] = useState(false);
  const [showNFCModal, setShowNFCModal] = useState(false);
  const [nfcAction, setNfcAction] = useState<"in" | "out">("in");
  const [comment, setComment] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  const clockScale = useSharedValue(1);
  const pulseAnim = useSharedValue(0);

  useEffect(() => {
    pulseAnim.value = withRepeat(withTiming(1, { duration: 1500 }), -1, true);
  }, [pulseAnim]);

  const { data: todayEntry, isLoading: todayLoading } = useQuery({
    queryKey: ["timesheet-today"],
    queryFn: () => api.get<TimesheetEntry | null>("/api/timesheet/today"),
  });

  const { data: stats } = useQuery({
    queryKey: ["timesheet-stats"],
    queryFn: () => api.get<{ totalHours: number; daysWorked: number } | null>("/api/timesheet/stats"),
  });

  const isClockedIn = todayEntry?.status === "in_progress";
  const isSubmitted = todayEntry?.status === "submitted";

  const clockInMutation = useMutation({
    mutationFn: (method: ClockMethod) =>
      api.post<TimesheetEntry>("/api/timesheet/clock-in", { method, isOffsite: false }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["timesheet-today"] });
      queryClient.invalidateQueries({ queryKey: ["timesheet-stats"] });
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    },
    onError: (err: any) => {
      const msg = err?.message ?? "";
      if (!msg.includes("ALREADY_CLOCKED_IN")) {
        Alert.alert("Error", "Failed to clock in. Please try again.");
      }
    },
  });

  const clockOutMutation = useMutation({
    mutationFn: ({ method, clockOutComment }: { method: ClockMethod; clockOutComment: string }) =>
      api.post<TimesheetEntry>("/api/timesheet/clock-out", {
        entryId: todayEntry?.id ?? "", method, comment: clockOutComment || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["timesheet-today"] });
      queryClient.invalidateQueries({ queryKey: ["timesheet-stats"] });
      setShowCommentModal(false);
      setComment("");
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    },
    onError: () => {
      Alert.alert("Error", "Failed to clock out. Please try again.");
    },
  });

  const { mutate: clockInMutate } = clockInMutation;
  const performClockIn = useCallback((method: ClockMethod) => {
    clockScale.value = withSpring(0.92, { damping: 15 }, () => {
      clockScale.value = withSpring(1, { damping: 15 });
    });
    clockInMutate(method);
  }, [clockScale, clockInMutate]);

  const handleClockPress = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    if (isClockedIn) {
      if (!todayEntry?.id) {
        Alert.alert("No active entry found. Please refresh.");
        return;
      }
      if (selectedMethod === "qr") { setShowQRScanner(true); }
      else if (selectedMethod === "nfc") { setNfcAction("out"); setShowNFCModal(true); }
      else { setShowCommentModal(true); }
    } else {
      if (selectedMethod === "qr") { setShowQRScanner(true); }
      else if (selectedMethod === "nfc") { setNfcAction("in"); setShowNFCModal(true); }
      else { performClockIn("manual"); }
    }
  };

  const handleQRScanned = (data: string) => {
    setShowQRScanner(false);
    if (isClockedIn) {
      clockOutMutation.mutate({ method: "qr", clockOutComment: comment });
    } else {
      clockInMutation.mutate("qr");
    }
  };

  const handleNFCConfirm = () => {
    setShowNFCModal(false);
    if (nfcAction === "out") { setShowCommentModal(true); }
    else { performClockIn("nfc"); }
  };

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["timesheet-today"] }),
      queryClient.invalidateQueries({ queryKey: ["timesheet-stats"] }),
    ]);
    setRefreshing(false);
  }, [queryClient]);

  const clockAnimStyle = useAnimatedStyle(() => ({ transform: [{ scale: clockScale.value }] }));
  const pulseStyle = useAnimatedStyle(() => ({
    opacity: interpolate(pulseAnim.value, [0, 1], [0.15, 0.4]),
    transform: [{ scale: interpolate(pulseAnim.value, [0, 1], [1, 1.2]) }],
  }));

  const userName = session?.user?.name?.split(" ")[0] ?? "there";
  const isPending = clockInMutation.isPending || clockOutMutation.isPending;

  return (
    <View style={{ flex: 1, backgroundColor: "#0A0F1E" }}>
      <SafeAreaView style={{ flex: 1 }} edges={["top"]}>
        <ScrollView showsVerticalScrollIndicator={false}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#3B82F6" />}
          contentContainerStyle={{ paddingBottom: 32 }}>

          {/* Header */}
          <Animated.View entering={FadeInDown.delay(50)} style={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: 4 }}>
            <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
              <View>
                <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#6B7280" }}>{getGreeting()},</Text>
                <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 24, color: "#FFFFFF" }}>{userName}</Text>
              </View>
            </View>
          </Animated.View>

          <LiveClock />

          {/* Status card */}
          <Animated.View entering={FadeInDown.delay(150)} style={{ paddingHorizontal: 20, marginBottom: 16 }}>
            <View style={{
              backgroundColor: "#111827", borderRadius: 20, padding: 20, borderWidth: 1,
              borderColor: isClockedIn ? "#3B82F640" : isSubmitted ? "#10B98140" : "#1C2438",
            }}>
              {todayLoading ? (
                <ActivityIndicator color="#3B82F6" />
              ) : isClockedIn ? (
                <View>
                  <View style={{ flexDirection: "row", alignItems: "center", marginBottom: 14 }}>
                    <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: "#10B981", marginRight: 8 }} />
                    <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 13, color: "#10B981", flex: 1 }}>CLOCKED IN</Text>
                    <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#4B5563" }}>
                      via {todayEntry?.clockInMethod ?? "manual"}
                    </Text>
                  </View>
                  <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
                    <View>
                      <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>Time In</Text>
                      <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 26, color: "#FFFFFF" }}>{todayEntry?.timeIn}</Text>
                    </View>
                    <View style={{ alignItems: "flex-end" }}>
                      <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>Duration</Text>
                      {todayEntry?.timeIn
                        ? <ElapsedTimer timeIn={todayEntry.timeIn} />
                        : <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 22, color: "#3B82F6" }}>--</Text>}
                    </View>
                  </View>
                </View>
              ) : isSubmitted ? (
                <View>
                  <View style={{ flexDirection: "row", alignItems: "center", marginBottom: 14 }}>
                    <CheckCircle size={15} color="#10B981" style={{ marginRight: 8 }} />
                    <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 13, color: "#10B981", flex: 1 }}>
                      SHIFT COMPLETE
                    </Text>
                    <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>
                      Tap below to clock in again
                    </Text>
                  </View>
                  <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
                    <View>
                      <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>In</Text>
                      <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 22, color: "#FFFFFF" }}>{todayEntry?.timeIn}</Text>
                    </View>
                    <View>
                      <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>Out</Text>
                      <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 22, color: "#FFFFFF" }}>{todayEntry?.timeOut}</Text>
                    </View>
                    <View style={{ alignItems: "flex-end" }}>
                      <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>Total</Text>
                      <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 22, color: "#10B981" }}>
                        {todayEntry?.totalHours?.toFixed(1)}h
                      </Text>
                    </View>
                  </View>
                  {!!todayEntry?.comment && (
                    <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#6B7280", marginTop: 10, fontStyle: "italic" }}>
                      "{todayEntry.comment}"
                    </Text>
                  )}
                </View>
              ) : (
                <View>
                  <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 14, color: "#F59E0B" }}>NOT YET CLOCKED IN</Text>
                  <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#6B7280", marginTop: 4, lineHeight: 20 }}>
                    Choose a clock method below and tap the button to start your day.
                  </Text>
                </View>
              )}
            </View>
          </Animated.View>

          {/* Method selector */}
          {!isClockedIn && (
            <Animated.View entering={FadeInDown.delay(200)} style={{ paddingHorizontal: 20, marginBottom: 20 }}>
              <Text style={{ fontFamily: "DMSans_500Medium", fontSize: 12, color: "#6B7280", marginBottom: 10, letterSpacing: 0.5 }}>
                CLOCK METHOD
              </Text>
              <View style={{ flexDirection: "row", gap: 8 }}>
                {METHODS.map((m) => {
                  const Icon = m.icon;
                  const isActive = selectedMethod === m.id;
                  return (
                    <Pressable key={m.id}
                      onPress={() => { setSelectedMethod(m.id); Haptics.selectionAsync(); }}
                      style={({ pressed }) => ({
                        flex: 1, backgroundColor: isActive ? "#1E3A5F" : "#111827",
                        borderRadius: 14, paddingVertical: 14, alignItems: "center",
                        borderWidth: 1.5, borderColor: isActive ? "#3B82F6" : "#1C2438",
                        opacity: pressed ? 0.75 : 1,
                      })}>
                      <Icon size={20} color={isActive ? "#3B82F6" : "#4B5563"} />
                      <Text style={{
                        fontFamily: isActive ? "DMSans_700Bold" : "DMSans_400Regular",
                        fontSize: 11, color: isActive ? "#3B82F6" : "#6B7280", marginTop: 6, letterSpacing: 0.3,
                      }}>{m.label}</Text>
                    </Pressable>
                  );
                })}
              </View>
              {selectedMethod === "qr" && (
                <Animated.View entering={FadeIn}>
                  <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#4B5563", marginTop: 8, textAlign: "center" }}>
                    Camera will open to scan the QR code at your worksite
                  </Text>
                </Animated.View>
              )}
              {selectedMethod === "nfc" && (
                <Animated.View entering={FadeIn}>
                  <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#4B5563", marginTop: 8, textAlign: "center" }}>
                    Hold phone near the NFC tag at the entrance to clock in/out
                  </Text>
                </Animated.View>
              )}
            </Animated.View>
          )}

          {/* Big clock button */}
          <Animated.View entering={FadeInDown.delay(250)} style={{ marginBottom: 28, alignItems: "center" }}>
            <Animated.View style={[{ position: "relative" }, clockAnimStyle]}>
              {!!isClockedIn && (
                <Animated.View style={[{
                  position: "absolute", width: 200, height: 200, borderRadius: 100,
                  backgroundColor: "#EF4444", left: -20, top: -20,
                }, pulseStyle]} />
              )}
              <Pressable onPress={handleClockPress} disabled={isPending} testID="clock-button"
                style={{
                  width: 160, height: 160, borderRadius: 80,
                  backgroundColor: isClockedIn ? "#EF4444" : "#3B82F6",
                  alignItems: "center", justifyContent: "center",
                  shadowColor: isClockedIn ? "#EF4444" : "#3B82F6",
                  shadowOpacity: 0.5, shadowRadius: 28, shadowOffset: { width: 0, height: 10 },
                  elevation: 12,
                }}>
                {isPending ? (
                  <ActivityIndicator color="#FFFFFF" size="large" />
                ) : (
                  <>
                    {isClockedIn
                      ? <LogOut size={38} color="#FFFFFF" />
                      : selectedMethod === "qr"
                        ? <QrCode size={38} color="#FFFFFF" />
                        : selectedMethod === "nfc"
                          ? <ScanLine size={38} color="#FFFFFF" />
                          : <LogIn size={38} color="#FFFFFF" />}
                    <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 13, color: "#FFFFFF", marginTop: 8, letterSpacing: 0.5 }}>
                      {isClockedIn ? "CLOCK OUT" : "CLOCK IN"}
                    </Text>
                  </>
                )}
              </Pressable>
            </Animated.View>
          </Animated.View>

          {/* Monthly stats */}
          <Animated.View entering={FadeInDown.delay(300)} style={{ paddingHorizontal: 20 }}>
            <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#FFFFFF", marginBottom: 12 }}>
              This Month
            </Text>
            <View style={{ flexDirection: "row", gap: 12 }}>
              <View style={{ flex: 1, backgroundColor: "#111827", borderRadius: 16, padding: 16, borderWidth: 1, borderColor: "#1C2438" }}>
                <TrendingUp size={18} color="#3B82F6" style={{ marginBottom: 8 }} />
                <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 26, color: "#FFFFFF" }}>
                  {stats?.totalHours?.toFixed(1) ?? "0"}
                </Text>
                <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>Total hours</Text>
              </View>
              <View style={{ flex: 1, backgroundColor: "#111827", borderRadius: 16, padding: 16, borderWidth: 1, borderColor: "#1C2438" }}>
                <Calendar size={18} color="#F59E0B" style={{ marginBottom: 8 }} />
                <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 26, color: "#FFFFFF" }}>
                  {stats?.daysWorked ?? "0"}
                </Text>
                <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280" }}>Days worked</Text>
              </View>
            </View>
          </Animated.View>
        </ScrollView>
      </SafeAreaView>

      <QRScannerModal visible={showQRScanner} onScanned={handleQRScanned}
        onClose={() => setShowQRScanner(false)} />

      <NFCScanModal visible={showNFCModal} action={nfcAction}
        onConfirm={handleNFCConfirm} onClose={() => setShowNFCModal(false)} />

      <Modal visible={showCommentModal} transparent animationType="slide">
        <View style={{ flex: 1, backgroundColor: "#00000090", justifyContent: "flex-end" }}>
          <View style={{ backgroundColor: "#111827", borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 24 }}>
            <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 22, color: "#FFFFFF", marginBottom: 6 }}>
              Clock Out
            </Text>
            <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 14, color: "#9CA3AF", marginBottom: 20 }}>
              Add an optional note about your work today
            </Text>
            <TextInput value={comment} onChangeText={setComment}
              placeholder="What did you work on today?" placeholderTextColor="#4B5563"
              multiline numberOfLines={3}
              style={{
                backgroundColor: "#1C2438", borderRadius: 12, padding: 16, color: "#FFFFFF",
                fontFamily: "DMSans_400Regular", fontSize: 15, borderWidth: 1, borderColor: "#2D3748",
                marginBottom: 16, minHeight: 80, textAlignVertical: "top",
              }} />
            <View style={{ flexDirection: "row", gap: 12 }}>
              <Pressable onPress={() => { setShowCommentModal(false); setComment(""); }}
                style={({ pressed }) => ({
                  flex: 1, backgroundColor: "#1C2438", borderRadius: 14,
                  paddingVertical: 16, alignItems: "center", opacity: pressed ? 0.75 : 1,
                })}>
                <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#9CA3AF" }}>Cancel</Text>
              </Pressable>
              <Pressable
                onPress={() => clockOutMutation.mutate({ method: selectedMethod, clockOutComment: comment })}
                disabled={clockOutMutation.isPending}
                style={({ pressed }) => ({
                  flex: 2, backgroundColor: "#EF4444", borderRadius: 14,
                  paddingVertical: 16, alignItems: "center", opacity: pressed ? 0.75 : 1,
                })}>
                {clockOutMutation.isPending
                  ? <ActivityIndicator color="#FFFFFF" />
                  : <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#FFFFFF" }}>Clock Out</Text>}
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}
