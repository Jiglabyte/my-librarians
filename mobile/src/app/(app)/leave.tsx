import React, { useState } from "react";
import {
  View, Text, Pressable, ScrollView, Modal, TextInput,
  ActivityIndicator, RefreshControl, Platform, Alert,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Animated, { FadeInDown, FadeIn } from "react-native-reanimated";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import * as Haptics from "expo-haptics";
import { api } from "@/lib/api/api";
import type { LeaveRequest } from "@/lib/types";
import { Plus, X, Calendar, Trash2, Download, FileText } from "lucide-react-native";
import DateTimePicker from "@react-native-community/datetimepicker";

type LeaveType = "annual" | "sick" | "away_from_office" | "public_holiday" | "emergency" | "day_off";

const LEAVE_TYPES: { id: LeaveType; label: string; desc: string; color: string; bg: string }[] = [
  { id: "annual", label: "Annual Leave", desc: "Planned time off", color: "#3B82F6", bg: "#1E3A5F" },
  { id: "sick", label: "Sick Day", desc: "Illness or medical", color: "#EF4444", bg: "#4A1818" },
  { id: "away_from_office", label: "Away from Office", desc: "Working remotely or offsite", color: "#F59E0B", bg: "#4A3000" },
  { id: "public_holiday", label: "Public Holiday", desc: "Official public holiday", color: "#10B981", bg: "#0D3B2E" },
  { id: "emergency", label: "Emergency", desc: "Urgent personal matter", color: "#A855F7", bg: "#2D1B4A" },
  { id: "day_off", label: "Day Off", desc: "Unpaid or comp day off", color: "#6B7280", bg: "#1C2438" },
];

function getLeaveType(id: string) {
  return LEAVE_TYPES.find((t) => t.id === id) ?? LEAVE_TYPES[0]!;
}

function formatDate(dateStr: string) {
  return new Date(dateStr).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function formatDateShort(dateStr: string) {
  return new Date(dateStr).toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function getDayCount(start: string, end: string) {
  const diff = new Date(end).getTime() - new Date(start).getTime();
  return Math.max(1, Math.ceil(diff / (1000 * 60 * 60 * 24)) + 1);
}

function getCurrentMonthLabel() {
  return new Date().toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

function exportToCSV(leaves: LeaveRequest[]) {
  const now = new Date();
  const monthLeaves = leaves.filter((l) => {
    const d = new Date(l.startDate);
    return d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear();
  });
  const rows = [
    ["Leave Type", "Start Date", "End Date", "Days", "Note"],
    ...monthLeaves.map((l) => {
      const days = getDayCount(l.startDate, l.endDate);
      return [getLeaveType(l.leaveType).label, formatDate(l.startDate), formatDate(l.endDate), String(days), l.comment ?? ""];
    }),
  ];
  const csv = rows.map((r) => r.map((cell) => `"${cell}"`).join(",")).join("\n");
  Alert.alert("Export CSV", `${getCurrentMonthLabel()} — ${monthLeaves.length} entr${monthLeaves.length === 1 ? "y" : "ies"}\n\n${csv}`, [{ text: "OK" }]);
}

export default function LeaveScreen() {
  const queryClient = useQueryClient();
  const [showModal, setShowModal] = useState(false);
  const [leaveType, setLeaveType] = useState<LeaveType>("annual");
  const [singleDay, setSingleDay] = useState(true);
  const [startDate, setStartDate] = useState(new Date().toISOString().split("T")[0]!);
  const [endDate, setEndDate] = useState(new Date().toISOString().split("T")[0]!);
  const [comment, setComment] = useState("");
  const [showStartPicker, setShowStartPicker] = useState(false);
  const [showEndPicker, setShowEndPicker] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const { data: leaves = [], isLoading } = useQuery({
    queryKey: ["leave-requests"],
    queryFn: () => api.get<LeaveRequest[]>("/api/leave"),
  });

  const createMutation = useMutation({
    mutationFn: () =>
      api.post("/api/leave", {
        leaveType,
        startDate,
        endDate: singleDay ? startDate : endDate,
        comment: comment.trim() || undefined,
        status: "approved",
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["leave-requests"] });
      setShowModal(false);
      setComment("");
      setLeaveType("annual");
      setSingleDay(true);
      setStartDate(new Date().toISOString().split("T")[0]!);
      setEndDate(new Date().toISOString().split("T")[0]!);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => api.delete(`/api/leave/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["leave-requests"] });
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    },
  });

  const onRefresh = async () => {
    setRefreshing(true);
    await queryClient.invalidateQueries({ queryKey: ["leave-requests"] });
    setRefreshing(false);
  };

  const openModal = () => {
    setShowModal(true);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  };

  const closeModal = () => {
    setShowModal(false);
    setComment("");
    setLeaveType("annual");
    setSingleDay(true);
    setStartDate(new Date().toISOString().split("T")[0]!);
    setEndDate(new Date().toISOString().split("T")[0]!);
    setShowStartPicker(false);
    setShowEndPicker(false);
  };

  const handleDelete = (id: string) => {
    Alert.alert("Delete Leave", "Are you sure you want to remove this leave entry?", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: () => deleteMutation.mutate(id),
      },
    ]);
  };

  const selectedType = getLeaveType(leaveType);

  // Group leaves by month
  const grouped = leaves.reduce<Record<string, LeaveRequest[]>>((acc, l) => {
    const key = new Date(l.startDate).toLocaleDateString("en-US", { month: "long", year: "numeric" });
    (acc[key] ??= []).push(l);
    return acc;
  }, {});

  const sortedMonths = Object.keys(grouped).sort(
    (a, b) => new Date(b).getTime() - new Date(a).getTime()
  );

  // Summary stats
  const now = new Date();
  const thisYear = leaves.filter((l) => new Date(l.startDate).getFullYear() === now.getFullYear());
  const totalDays = thisYear.reduce((sum, l) => sum + getDayCount(l.startDate, l.endDate), 0);

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: "#0F172A" }}>
      {/* Header */}
      <Animated.View entering={FadeIn.duration(400)} style={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: 12 }}>
        <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center" }}>
          <View>
            <Text style={{ fontSize: 28, fontWeight: "800", color: "#F8FAFC", letterSpacing: -0.5 }}>Leave</Text>
            <Text style={{ fontSize: 14, color: "#94A3B8", marginTop: 2 }}>
              {totalDays} day{totalDays !== 1 ? "s" : ""} taken in {now.getFullYear()}
            </Text>
          </View>
          <View style={{ flexDirection: "row", gap: 10 }}>
            <Pressable
              onPress={() => exportToCSV(leaves)}
              style={{
                backgroundColor: "#1E293B",
                borderRadius: 12,
                width: 44,
                height: 44,
                justifyContent: "center",
                alignItems: "center",
                borderWidth: 1,
                borderColor: "#334155",
              }}
            >
              <Download size={20} color="#94A3B8" />
            </Pressable>
            <Pressable
              onPress={openModal}
              style={{
                backgroundColor: "#3B82F6",
                borderRadius: 12,
                width: 44,
                height: 44,
                justifyContent: "center",
                alignItems: "center",
              }}
            >
              <Plus size={22} color="#FFFFFF" />
            </Pressable>
          </View>
        </View>

        {/* Quick stats bar */}
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 16 }}>
          <View style={{ flexDirection: "row", gap: 8 }}>
            {LEAVE_TYPES.map((lt) => {
              const count = thisYear.filter((l) => l.leaveType === lt.id).length;
              if (count === 0) return null;
              return (
                <View
                  key={lt.id}
                  style={{
                    backgroundColor: lt.bg,
                    borderRadius: 10,
                    paddingHorizontal: 12,
                    paddingVertical: 6,
                    flexDirection: "row",
                    alignItems: "center",
                    gap: 6,
                  }}
                >
                  <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: lt.color }} />
                  <Text style={{ color: lt.color, fontSize: 13, fontWeight: "600" }}>
                    {count} {lt.label}
                  </Text>
                </View>
              );
            })}
          </View>
        </ScrollView>
      </Animated.View>

      {/* Leave list */}
      {isLoading ? (
        <View style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
          <ActivityIndicator size="large" color="#3B82F6" />
        </View>
      ) : leaves.length === 0 ? (
        <View style={{ flex: 1, justifyContent: "center", alignItems: "center", paddingHorizontal: 40 }}>
          <FileText size={48} color="#334155" />
          <Text style={{ fontSize: 18, fontWeight: "700", color: "#CBD5E1", marginTop: 16, textAlign: "center" }}>
            No leave recorded
          </Text>
          <Text style={{ fontSize: 14, color: "#64748B", marginTop: 8, textAlign: "center" }}>
            Tap the + button to add your first leave entry
          </Text>
        </View>
      ) : (
        <ScrollView
          style={{ flex: 1 }}
          contentContainerStyle={{ paddingHorizontal: 20, paddingBottom: 100 }}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#3B82F6" />}
        >
          {sortedMonths.map((month, mi) => (
            <Animated.View key={month} entering={FadeInDown.delay(mi * 80).duration(400)}>
              <Text style={{ fontSize: 15, fontWeight: "700", color: "#64748B", marginTop: mi === 0 ? 8 : 24, marginBottom: 10, textTransform: "uppercase", letterSpacing: 0.5 }}>
                {month}
              </Text>
              {grouped[month]!.map((leave, li) => {
                const lt = getLeaveType(leave.leaveType);
                const days = getDayCount(leave.startDate, leave.endDate);
                const isSingle = leave.startDate === leave.endDate;
                return (
                  <Animated.View
                    key={leave.id}
                    entering={FadeInDown.delay(mi * 80 + li * 50).duration(350)}
                    style={{
                      backgroundColor: "#1E293B",
                      borderRadius: 14,
                      padding: 16,
                      marginBottom: 10,
                      borderWidth: 1,
                      borderColor: "#334155",
                      borderLeftWidth: 4,
                      borderLeftColor: lt.color,
                    }}
                  >
                    <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start" }}>
                      <View style={{ flex: 1, marginRight: 12 }}>
                        <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
                          <Text style={{ fontSize: 16, fontWeight: "700", color: "#F1F5F9" }}>{lt.label}</Text>
                          <View style={{ backgroundColor: lt.bg, borderRadius: 6, paddingHorizontal: 8, paddingVertical: 2 }}>
                            <Text style={{ fontSize: 12, fontWeight: "600", color: lt.color }}>
                              {days} day{days > 1 ? "s" : ""}
                            </Text>
                          </View>
                        </View>
                        <View style={{ flexDirection: "row", alignItems: "center", gap: 4, marginTop: 6 }}>
                          <Calendar size={13} color="#64748B" />
                          <Text style={{ fontSize: 13, color: "#94A3B8" }}>
                            {isSingle ? formatDate(leave.startDate) : `${formatDateShort(leave.startDate)} — ${formatDateShort(leave.endDate)}`}
                          </Text>
                        </View>
                        {leave.comment ? (
                          <Text style={{ fontSize: 13, color: "#64748B", marginTop: 6 }} numberOfLines={2}>
                            {leave.comment}
                          </Text>
                        ) : null}
                      </View>
                      <Pressable
                        onPress={() => handleDelete(leave.id)}
                        hitSlop={12}
                        style={{
                          backgroundColor: "#4A181833",
                          borderRadius: 8,
                          width: 36,
                          height: 36,
                          justifyContent: "center",
                          alignItems: "center",
                        }}
                      >
                        <Trash2 size={16} color="#EF4444" />
                      </Pressable>
                    </View>
                  </Animated.View>
                );
              })}
            </Animated.View>
          ))}
        </ScrollView>
      )}

      {/* Create Leave Modal */}
      <Modal visible={showModal} animationType="slide" presentationStyle="pageSheet" onRequestClose={closeModal}>
        <SafeAreaView style={{ flex: 1, backgroundColor: "#0F172A" }}>
          {/* Modal Header */}
          <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "center", paddingHorizontal: 20, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: "#1E293B" }}>
            <Text style={{ fontSize: 20, fontWeight: "800", color: "#F8FAFC" }}>New Leave</Text>
            <Pressable onPress={closeModal} hitSlop={12} style={{ backgroundColor: "#1E293B", borderRadius: 10, width: 36, height: 36, justifyContent: "center", alignItems: "center" }}>
              <X size={18} color="#94A3B8" />
            </Pressable>
          </View>

          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 20, paddingBottom: 40 }}>
            {/* Leave Type */}
            <Text style={{ fontSize: 14, fontWeight: "600", color: "#94A3B8", marginBottom: 10 }}>Leave Type</Text>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 8, marginBottom: 24 }}>
              {LEAVE_TYPES.map((lt) => {
                const active = leaveType === lt.id;
                return (
                  <Pressable
                    key={lt.id}
                    onPress={() => { setLeaveType(lt.id); Haptics.selectionAsync(); }}
                    style={{
                      backgroundColor: active ? lt.bg : "#1E293B",
                      borderRadius: 10,
                      paddingHorizontal: 14,
                      paddingVertical: 10,
                      borderWidth: 1.5,
                      borderColor: active ? lt.color : "#334155",
                    }}
                  >
                    <Text style={{ fontSize: 14, fontWeight: "600", color: active ? lt.color : "#94A3B8" }}>{lt.label}</Text>
                    <Text style={{ fontSize: 11, color: active ? lt.color + "99" : "#64748B", marginTop: 2 }}>{lt.desc}</Text>
                  </Pressable>
                );
              })}
            </View>

            {/* Duration Toggle */}
            <Text style={{ fontSize: 14, fontWeight: "600", color: "#94A3B8", marginBottom: 10 }}>Duration</Text>
            <View style={{ flexDirection: "row", gap: 8, marginBottom: 20 }}>
              <Pressable
                onPress={() => { setSingleDay(true); Haptics.selectionAsync(); }}
                style={{
                  flex: 1,
                  backgroundColor: singleDay ? "#1E3A5F" : "#1E293B",
                  borderRadius: 10,
                  paddingVertical: 12,
                  alignItems: "center",
                  borderWidth: 1.5,
                  borderColor: singleDay ? "#3B82F6" : "#334155",
                }}
              >
                <Text style={{ fontSize: 14, fontWeight: "600", color: singleDay ? "#3B82F6" : "#94A3B8" }}>Single Day</Text>
              </Pressable>
              <Pressable
                onPress={() => { setSingleDay(false); Haptics.selectionAsync(); }}
                style={{
                  flex: 1,
                  backgroundColor: !singleDay ? "#1E3A5F" : "#1E293B",
                  borderRadius: 10,
                  paddingVertical: 12,
                  alignItems: "center",
                  borderWidth: 1.5,
                  borderColor: !singleDay ? "#3B82F6" : "#334155",
                }}
              >
                <Text style={{ fontSize: 14, fontWeight: "600", color: !singleDay ? "#3B82F6" : "#94A3B8" }}>Date Range</Text>
              </Pressable>
            </View>

            {/* Date Pickers */}
            <Text style={{ fontSize: 14, fontWeight: "600", color: "#94A3B8", marginBottom: 10 }}>
              {singleDay ? "Date" : "Start Date"}
            </Text>
            <Pressable
              onPress={() => setShowStartPicker(true)}
              style={{
                backgroundColor: "#1E293B",
                borderRadius: 10,
                paddingHorizontal: 16,
                paddingVertical: 14,
                borderWidth: 1,
                borderColor: "#334155",
                flexDirection: "row",
                alignItems: "center",
                gap: 10,
                marginBottom: showStartPicker ? 8 : 20,
              }}
            >
              <Calendar size={16} color="#3B82F6" />
              <Text style={{ fontSize: 15, color: "#F1F5F9", fontWeight: "500" }}>{formatDate(startDate)}</Text>
            </Pressable>
            {showStartPicker && (
              <View style={{ marginBottom: 20 }}>
                <DateTimePicker
                  value={new Date(startDate + "T12:00:00")}
                  mode="date"
                  display={Platform.OS === "ios" ? "inline" : "default"}
                  themeVariant="dark"
                  onChange={(_, date) => {
                    if (Platform.OS === "android") setShowStartPicker(false);
                    if (date) {
                      const ds = date.toISOString().split("T")[0]!;
                      setStartDate(ds);
                      if (ds > endDate) setEndDate(ds);
                    }
                  }}
                />
                {Platform.OS === "ios" && (
                  <Pressable onPress={() => setShowStartPicker(false)} style={{ alignSelf: "flex-end", marginTop: 4 }}>
                    <Text style={{ color: "#3B82F6", fontSize: 14, fontWeight: "600" }}>Done</Text>
                  </Pressable>
                )}
              </View>
            )}

            {!singleDay && (
              <>
                <Text style={{ fontSize: 14, fontWeight: "600", color: "#94A3B8", marginBottom: 10 }}>End Date</Text>
                <Pressable
                  onPress={() => setShowEndPicker(true)}
                  style={{
                    backgroundColor: "#1E293B",
                    borderRadius: 10,
                    paddingHorizontal: 16,
                    paddingVertical: 14,
                    borderWidth: 1,
                    borderColor: "#334155",
                    flexDirection: "row",
                    alignItems: "center",
                    gap: 10,
                    marginBottom: showEndPicker ? 8 : 20,
                  }}
                >
                  <Calendar size={16} color="#3B82F6" />
                  <Text style={{ fontSize: 15, color: "#F1F5F9", fontWeight: "500" }}>{formatDate(endDate)}</Text>
                </Pressable>
                {showEndPicker && (
                  <View style={{ marginBottom: 20 }}>
                    <DateTimePicker
                      value={new Date(endDate + "T12:00:00")}
                      mode="date"
                      display={Platform.OS === "ios" ? "inline" : "default"}
                      minimumDate={new Date(startDate + "T12:00:00")}
                      themeVariant="dark"
                      onChange={(_, date) => {
                        if (Platform.OS === "android") setShowEndPicker(false);
                        if (date) setEndDate(date.toISOString().split("T")[0]!);
                      }}
                    />
                    {Platform.OS === "ios" && (
                      <Pressable onPress={() => setShowEndPicker(false)} style={{ alignSelf: "flex-end", marginTop: 4 }}>
                        <Text style={{ color: "#3B82F6", fontSize: 14, fontWeight: "600" }}>Done</Text>
                      </Pressable>
                    )}
                  </View>
                )}

                {/* Day count preview */}
                <View style={{ backgroundColor: "#1E3A5F", borderRadius: 10, padding: 12, marginBottom: 20, alignItems: "center" }}>
                  <Text style={{ fontSize: 14, fontWeight: "600", color: "#3B82F6" }}>
                    {getDayCount(startDate, endDate)} day{getDayCount(startDate, endDate) > 1 ? "s" : ""} selected
                  </Text>
                </View>
              </>
            )}

            {/* Comment */}
            <Text style={{ fontSize: 14, fontWeight: "600", color: "#94A3B8", marginBottom: 10 }}>Note (optional)</Text>
            <TextInput
              value={comment}
              onChangeText={setComment}
              placeholder="Add a note..."
              placeholderTextColor="#475569"
              multiline
              numberOfLines={3}
              style={{
                backgroundColor: "#1E293B",
                borderRadius: 10,
                paddingHorizontal: 16,
                paddingVertical: 14,
                borderWidth: 1,
                borderColor: "#334155",
                color: "#F1F5F9",
                fontSize: 15,
                minHeight: 80,
                textAlignVertical: "top",
                marginBottom: 32,
              }}
            />

            {/* Submit */}
            <Pressable
              onPress={() => createMutation.mutate()}
              disabled={createMutation.isPending}
              style={{
                backgroundColor: selectedType.color,
                borderRadius: 14,
                paddingVertical: 16,
                alignItems: "center",
                opacity: createMutation.isPending ? 0.6 : 1,
              }}
            >
              {createMutation.isPending ? (
                <ActivityIndicator color="#FFFFFF" />
              ) : (
                <Text style={{ fontSize: 16, fontWeight: "700", color: "#FFFFFF" }}>
                  Add {selectedType.label}
                </Text>
              )}
            </Pressable>
          </ScrollView>
        </SafeAreaView>
      </Modal>
    </SafeAreaView>
  );
}
