import React, { useState, useCallback } from "react";
import {
  View, Text, Pressable, ScrollView, TextInput, Switch, Alert,
  ActivityIndicator, Platform,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Animated, { FadeInDown } from "react-native-reanimated";
import * as Haptics from "expo-haptics";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import DateTimePicker, { DateTimePickerEvent } from "@react-native-community/datetimepicker";
import { api } from "@/lib/api/api";
import { useSession, useInvalidateSession } from "@/lib/auth/use-session";
import { authClient } from "@/lib/auth/auth-client";
import type { UserProfile, LocationSettings } from "@/lib/types";
import {
  User, Building2, BadgeCheck, Bell, Clock, MapPin,
  Navigation, LogOut, ChevronRight, Save,
} from "lucide-react-native";

/* ─── helpers ────────────────────────────────────────────────────────── */

function getInitials(name?: string | null): string {
  if (!name) return "?";
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) return (parts[0]![0]! + parts[parts.length - 1]![0]!).toUpperCase();
  return name.slice(0, 2).toUpperCase();
}

function timeToDate(timeStr: string): Date {
  const [h, m] = timeStr.split(":").map(Number);
  const d = new Date();
  d.setHours(h ?? 7, m ?? 0, 0, 0);
  return d;
}

function dateToTime(d: Date): string {
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/* ─── section wrapper ────────────────────────────────────────────────── */

function Section({ title, delay, children }: { title: string; delay: number; children: React.ReactNode }) {
  return (
    <Animated.View entering={FadeInDown.delay(delay)} style={{ marginBottom: 20 }}>
      <Text style={{
        fontFamily: "DMSans_500Medium", fontSize: 12, color: "#6B7280",
        letterSpacing: 0.5, marginBottom: 10, paddingHorizontal: 20,
      }}>
        {title}
      </Text>
      <View style={{
        marginHorizontal: 20, backgroundColor: "#111827",
        borderRadius: 16, borderWidth: 1, borderColor: "#1C2438", overflow: "hidden",
      }}>
        {children}
      </View>
    </Animated.View>
  );
}

/* ─── editable row ───────────────────────────────────────────────────── */

function FieldRow({
  icon: Icon, label, value, onChangeText, editable = true, last = false,
}: {
  icon: React.ComponentType<{ size: number; color: string }>;
  label: string; value: string; onChangeText?: (t: string) => void;
  editable?: boolean; last?: boolean;
}) {
  return (
    <View style={{
      flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 14,
      borderBottomWidth: last ? 0 : 1, borderBottomColor: "#1C2438",
    }}>
      <Icon size={18} color="#4B5563" />
      <Text style={{
        fontFamily: "DMSans_400Regular", fontSize: 13, color: "#6B7280",
        width: 90, marginLeft: 12,
      }}>
        {label}
      </Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        editable={editable}
        style={{
          flex: 1, fontFamily: "DMSans_500Medium", fontSize: 14,
          color: editable ? "#FFFFFF" : "#4B5563",
          padding: 0,
        }}
        placeholderTextColor="#4B5563"
      />
    </View>
  );
}

/* ─── toggle row ─────────────────────────────────────────────────────── */

function ToggleRow({
  icon: Icon, label, value, onValueChange, last = false,
}: {
  icon: React.ComponentType<{ size: number; color: string }>;
  label: string; value: boolean; onValueChange: (v: boolean) => void; last?: boolean;
}) {
  return (
    <View style={{
      flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 14,
      borderBottomWidth: last ? 0 : 1, borderBottomColor: "#1C2438",
    }}>
      <Icon size={18} color="#4B5563" />
      <Text style={{
        fontFamily: "DMSans_400Regular", fontSize: 14, color: "#FFFFFF",
        flex: 1, marginLeft: 12,
      }}>
        {label}
      </Text>
      <Switch
        value={value}
        onValueChange={(v) => { Haptics.selectionAsync(); onValueChange(v); }}
        trackColor={{ false: "#1C2438", true: "#3B82F6" }}
        thumbColor="#FFFFFF"
      />
    </View>
  );
}

/* ─── time picker row ────────────────────────────────────────────────── */

function TimePickerRow({
  icon: Icon, label, time, onChange, last = false,
}: {
  icon: React.ComponentType<{ size: number; color: string }>;
  label: string; time: string; onChange: (t: string) => void; last?: boolean;
}) {
  const [showPicker, setShowPicker] = useState(false);

  const handleChange = (_event: DateTimePickerEvent, selectedDate?: Date) => {
    if (Platform.OS === "android") setShowPicker(false);
    if (selectedDate) onChange(dateToTime(selectedDate));
  };

  return (
    <View style={{
      borderBottomWidth: last ? 0 : 1, borderBottomColor: "#1C2438",
    }}>
      <Pressable
        onPress={() => setShowPicker(!showPicker)}
        style={{
          flexDirection: "row", alignItems: "center",
          paddingHorizontal: 16, paddingVertical: 14,
        }}
      >
        <Icon size={18} color="#4B5563" />
        <Text style={{
          fontFamily: "DMSans_400Regular", fontSize: 14, color: "#FFFFFF",
          flex: 1, marginLeft: 12,
        }}>
          {label}
        </Text>
        <Text style={{ fontFamily: "DMSans_500Medium", fontSize: 14, color: "#3B82F6", marginRight: 8 }}>
          {time}
        </Text>
        <ChevronRight size={16} color="#4B5563" />
      </Pressable>
      {showPicker && (
        <View style={{ paddingBottom: 8, alignItems: "center" }}>
          <DateTimePicker
            value={timeToDate(time)}
            mode="time"
            display={Platform.OS === "ios" ? "spinner" : "default"}
            onChange={handleChange}
            themeVariant="dark"
          />
          {Platform.OS === "ios" && (
            <Pressable onPress={() => setShowPicker(false)} style={{ paddingVertical: 8 }}>
              <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 14, color: "#3B82F6" }}>Done</Text>
            </Pressable>
          )}
        </View>
      )}
    </View>
  );
}

/* ═══════════════════════════════════════════════════════════════════════
   PROFILE SCREEN
   ═══════════════════════════════════════════════════════════════════════ */

export default function ProfileScreen() {
  const { data: session } = useSession();
  const invalidateSession = useInvalidateSession();
  const queryClient = useQueryClient();

  /* ── profile state ──────────────────────────────────────────────── */
  const [name, setName] = useState(session?.user?.name ?? "");
  const [department, setDepartment] = useState("");
  const [employeeId, setEmployeeId] = useState("");

  const { isLoading: profileLoading } = useQuery({
    queryKey: ["user-profile"],
    queryFn: async () => {
      const profile = await api.get<UserProfile>("/api/user/profile");
      if (profile) {
        setName(profile.name ?? "");
        setDepartment(profile.department ?? "");
        setEmployeeId(profile.employeeId ?? "");
      }
      return profile;
    },
  });

  const profileMutation = useMutation({
    mutationFn: () =>
      api.put<UserProfile>("/api/user/profile", { name, department, employeeId }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["user-profile"] });
      invalidateSession();
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      Alert.alert("Saved", "Your profile has been updated.");
    },
    onError: () => Alert.alert("Error", "Failed to save profile. Please try again."),
  });

  /* ── notification settings state ────────────────────────────────── */
  const [clockInReminder, setClockInReminder] = useState(true);
  const [clockInTime, setClockInTime] = useState("07:45");
  const [endOfDayReminder, setEndOfDayReminder] = useState(true);
  const [endOfDayTime, setEndOfDayTime] = useState("17:00");

  /* ── location settings state ────────────────────────────────────── */
  const [geofenceEnabled, setGeofenceEnabled] = useState(false);
  const [geofenceRadius, setGeofenceRadius] = useState("200");
  const [officeAddress, setOfficeAddress] = useState("");

  const { isLoading: locationLoading } = useQuery({
    queryKey: ["location-settings"],
    queryFn: async () => {
      const settings = await api.get<LocationSettings>("/api/user/location-settings");
      if (settings) {
        setGeofenceEnabled(settings.enabled);
        setGeofenceRadius(String(settings.radius));
        setOfficeAddress(settings.address ?? "");
      }
      return settings;
    },
  });

  const locationMutation = useMutation({
    mutationFn: () =>
      api.put<LocationSettings>("/api/user/location-settings", {
        enabled: geofenceEnabled,
        radius: parseInt(geofenceRadius, 10) || 200,
        address: officeAddress || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["location-settings"] });
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      Alert.alert("Saved", "Location settings updated.");
    },
    onError: () => Alert.alert("Error", "Failed to save location settings."),
  });

  /* ── sign out ───────────────────────────────────────────────────── */
  const [signingOut, setSigningOut] = useState(false);

  const handleSignOut = useCallback(() => {
    Alert.alert("Sign Out", "Are you sure you want to sign out?", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Sign Out",
        style: "destructive",
        onPress: async () => {
          setSigningOut(true);
          try {
            await authClient.signOut();
            invalidateSession();
          } catch {
            Alert.alert("Error", "Failed to sign out.");
          } finally {
            setSigningOut(false);
          }
        },
      },
    ]);
  }, [invalidateSession]);

  /* ── render ─────────────────────────────────────────────────────── */
  const initials = getInitials(name || session?.user?.name);
  const email = session?.user?.email ?? "";

  return (
    <View style={{ flex: 1, backgroundColor: "#0A0F1E" }}>
      <SafeAreaView style={{ flex: 1 }} edges={["top"]}>
        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 40 }}>

          {/* ── header ─────────────────────────────────────────────── */}
          <Animated.View entering={FadeInDown.delay(50)}
            style={{ alignItems: "center", paddingTop: 16, paddingBottom: 24 }}
          >
            <View style={{
              width: 80, height: 80, borderRadius: 40, backgroundColor: "#1E3A5F",
              alignItems: "center", justifyContent: "center",
              borderWidth: 2, borderColor: "#3B82F6", marginBottom: 12,
            }}>
              <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 28, color: "#3B82F6" }}>
                {initials}
              </Text>
            </View>
            <Text style={{ fontFamily: "DMSerifDisplay_400Regular", fontSize: 22, color: "#FFFFFF" }}>
              {name || "Your Name"}
            </Text>
            <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 13, color: "#6B7280", marginTop: 2 }}>
              {email}
            </Text>
          </Animated.View>

          {/* ── profile fields ─────────────────────────────────────── */}
          <Section title="PROFILE" delay={100}>
            {profileLoading ? (
              <View style={{ padding: 20 }}><ActivityIndicator color="#3B82F6" /></View>
            ) : (
              <>
                <FieldRow icon={User} label="Name" value={name} onChangeText={setName} />
                <FieldRow icon={Building2} label="Department" value={department} onChangeText={setDepartment} />
                <FieldRow icon={BadgeCheck} label="Employee ID" value={employeeId} onChangeText={setEmployeeId} last />
              </>
            )}
          </Section>

          <Animated.View entering={FadeInDown.delay(150)} style={{ paddingHorizontal: 20, marginBottom: 20 }}>
            <Pressable
              onPress={() => profileMutation.mutate()}
              disabled={profileMutation.isPending}
              style={({ pressed }) => ({
                backgroundColor: "#3B82F6", borderRadius: 14,
                paddingVertical: 16, alignItems: "center",
                flexDirection: "row", justifyContent: "center", gap: 8,
                opacity: pressed ? 0.75 : 1,
              })}
            >
              {profileMutation.isPending ? (
                <ActivityIndicator color="#FFFFFF" />
              ) : (
                <>
                  <Save size={18} color="#FFFFFF" />
                  <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#FFFFFF" }}>
                    Save Profile
                  </Text>
                </>
              )}
            </Pressable>
          </Animated.View>

          {/* ── notification settings ──────────────────────────────── */}
          <Section title="NOTIFICATIONS" delay={200}>
            <ToggleRow
              icon={Bell}
              label="Clock-in reminder"
              value={clockInReminder}
              onValueChange={setClockInReminder}
            />
            {clockInReminder && (
              <TimePickerRow
                icon={Clock}
                label="Reminder time"
                time={clockInTime}
                onChange={setClockInTime}
              />
            )}
            <ToggleRow
              icon={Bell}
              label="End-of-day reminder"
              value={endOfDayReminder}
              onValueChange={setEndOfDayReminder}
            />
            {endOfDayReminder && (
              <TimePickerRow
                icon={Clock}
                label="Reminder time"
                time={endOfDayTime}
                onChange={setEndOfDayTime}
                last
              />
            )}
          </Section>

          {/* ── location settings ──────────────────────────────────── */}
          <Section title="LOCATION" delay={250}>
            {locationLoading ? (
              <View style={{ padding: 20 }}><ActivityIndicator color="#3B82F6" /></View>
            ) : (
              <>
                <ToggleRow
                  icon={Navigation}
                  label="Geofence verification"
                  value={geofenceEnabled}
                  onValueChange={setGeofenceEnabled}
                />
                {geofenceEnabled && (
                  <>
                    <FieldRow
                      icon={MapPin}
                      label="Radius (m)"
                      value={geofenceRadius}
                      onChangeText={setGeofenceRadius}
                    />
                    <FieldRow
                      icon={Building2}
                      label="Office address"
                      value={officeAddress}
                      onChangeText={setOfficeAddress}
                      last
                    />
                  </>
                )}
              </>
            )}
          </Section>

          {geofenceEnabled && (
            <Animated.View entering={FadeInDown.delay(300)} style={{ paddingHorizontal: 20, marginBottom: 20 }}>
              <Pressable
                onPress={() => locationMutation.mutate()}
                disabled={locationMutation.isPending}
                style={({ pressed }) => ({
                  backgroundColor: "#1E3A5F", borderRadius: 14, borderWidth: 1, borderColor: "#3B82F6",
                  paddingVertical: 16, alignItems: "center",
                  flexDirection: "row", justifyContent: "center", gap: 8,
                  opacity: pressed ? 0.75 : 1,
                })}
              >
                {locationMutation.isPending ? (
                  <ActivityIndicator color="#3B82F6" />
                ) : (
                  <>
                    <Save size={18} color="#3B82F6" />
                    <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#3B82F6" }}>
                      Save Location Settings
                    </Text>
                  </>
                )}
              </Pressable>
            </Animated.View>
          )}

          {/* ── sign out ───────────────────────────────────────────── */}
          <Animated.View entering={FadeInDown.delay(350)} style={{ paddingHorizontal: 20, marginTop: 8, marginBottom: 20 }}>
            <Pressable
              onPress={handleSignOut}
              disabled={signingOut}
              style={({ pressed }) => ({
                backgroundColor: "#111827", borderRadius: 14,
                borderWidth: 1, borderColor: "#EF444440",
                paddingVertical: 16, alignItems: "center",
                flexDirection: "row", justifyContent: "center", gap: 8,
                opacity: pressed ? 0.75 : 1,
              })}
            >
              {signingOut ? (
                <ActivityIndicator color="#EF4444" />
              ) : (
                <>
                  <LogOut size={18} color="#EF4444" />
                  <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 15, color: "#EF4444" }}>
                    Sign Out
                  </Text>
                </>
              )}
            </Pressable>
          </Animated.View>

        </ScrollView>
      </SafeAreaView>
    </View>
  );
}
