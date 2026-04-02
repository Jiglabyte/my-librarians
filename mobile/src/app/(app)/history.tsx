import React, { useState, useRef, useCallback } from "react";
import {
  View,
  Text,
  Pressable,
  ScrollView,
  ActivityIndicator,
  RefreshControl,
  Modal,
  TextInput,
  Alert,
  FlatList,
  Linking,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Animated, { FadeInDown, FadeIn } from "react-native-reanimated";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import * as FileSystem from "expo-file-system";
import * as Sharing from "expo-sharing";
import * as Haptics from "expo-haptics";
import { api } from "@/lib/api/api";
import type { TimesheetEntry } from "@/lib/types";
import {
  CheckCircle, Clock, Download, X, Edit2, Plus, Zap, Table2, Trash2,
} from "lucide-react-native";

type Period = "week" | "month";

function getDateRange(period: Period) {
  const now = new Date();
  if (period === "week") {
    const start = new Date(now);
    start.setDate(now.getDate() - 6);
    return {
      startDate: start.toISOString().split("T")[0]!,
      endDate: now.toISOString().split("T")[0]!,
    };
  }
  return {
    startDate: new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split("T")[0]!,
    endDate: new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split("T")[0]!,
  };
}

function formatDay(dateStr: string) {
  return new Date(dateStr + "T12:00:00").toLocaleDateString("en-US", {
    weekday: "short", month: "short", day: "numeric",
  });
}

function getWorkdaysInRange(startDate: string, endDate: string): string[] {
  const days: string[] = [];
  const start = new Date(startDate + "T12:00:00");
  const end = new Date(endDate + "T12:00:00");
  const today = new Date();
  today.setHours(23, 59, 59, 999);
  while (start <= end && start <= today) {
    if (start.getDay() !== 0 && start.getDay() !== 6) {
      days.push(start.toISOString().split("T")[0]!);
    }
    start.setDate(start.getDate() + 1);
  }
  return days;
}

function isValidTime(t: string) {
  return /^([01]\d|2[0-3]):([0-5]\d)$/.test(t);
}

function generateTimeSlots(): string[] {
  const slots: string[] = [];
  for (let h = 0; h < 24; h++) {
    for (let m = 0; m < 60; m += 15) {
      slots.push(`${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`);
    }
  }
  return slots;
}

const ALL_SLOTS = generateTimeSlots();

function getNearestSlots(): string[] {
  const now = new Date();
  const totalMins = now.getHours() * 60 + now.getMinutes();
  const nearestIdx = Math.round(totalMins / 15);
  const indices = [nearestIdx - 1, nearestIdx, nearestIdx + 1]
    .map((i) => ((i % ALL_SLOTS.length) + ALL_SLOTS.length) % ALL_SLOTS.length)
    .filter((i, pos, arr) => arr.indexOf(i) === pos);
  return indices.map((i) => ALL_SLOTS[i]!);
}

function TimePicker({ value, onChange, label }: { value: string; onChange: (v: string) => void; label: string }) {
  const [open, setOpen] = useState(false);
  const listRef = useRef<FlatList>(null);
  const nearSlots = getNearestSlots();

  const handleOpen = useCallback(() => {
    setOpen(true);
    setTimeout(() => {
      const target = isValidTime(value) ? value : nearSlots[1] ?? "08:00";
      const idx = ALL_SLOTS.indexOf(target);
      if (idx >= 0 && listRef.current) {
        listRef.current.scrollToIndex({ index: idx, animated: false, viewPosition: 0.4 });
      }
    }, 100);
  }, [value, nearSlots]);

  const handleSelect = useCallback((slot: string) => {
    Haptics.selectionAsync();
    onChange(slot);
    setOpen(false);
  }, [onChange]);

  const displayValue = isValidTime(value) ? value : null;

  return (
    <View style={{ flex: 1 }}>
      <Text style={{ fontFamily: "DMSans_400Regular", fontSize: 12, color: "#6B7280", marginBottom: 6 }}>
        {label}
      </Text>
      <Pressable onPress={handleOpen} testID={`time-picker-${label.toLowerCase().replace(/\s/g, "-")}`}
        style={({ pressed }) => ({
          backgroundColor: pressed ? "#243050" : "#1C2438", borderRadius: 10,
          paddingVertical: 14, paddingHorizontal: 14, borderWidth: 1.5,
          borderColor: displayValue ? "#3B82F650" : "#2D3748", alignItems: "center", justifyContent: "center",
        })}>
        <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 22, color: displayValue ? "#FFFFFF" : "#4B5563", textAlign: "center" }}>
          {displayValue ?? "Select time"}
        </Text>
      </Pressable>
      <Modal visible={open} transparent animationType="slide">
        <View style={{ flex: 1 }}>
          <Pressable style={{ flex: 1, backgroundColor: "#00000060" }} onPress={() => setOpen(false)} />
          <View style={{ position: "absolute", bottom: 0, left: 0, right: 0, backgroundColor: "#111827", borderTopLeftRadius: 24, borderTopRightRadius: 24, maxHeight: "60%" }}>
            <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: 20, paddingTop: 18, paddingBottom: 12, borderBottomWidth: 1, borderBottomColor: "#1C2438" }}>
              <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 16, color: "#FFFFFF" }}>{label}</Text>
              <Pressable onPress={() => setOpen(false)} testID={`time-picker-done-${label.toLowerCase().replace(/\s/g, "-")}`}
                style={{ backgroundColor: "#3B82F6", borderRadius: 10, paddingHorizontal: 16, paddingVertical: 7 }}>
                <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 14, color: "#FFFFFF" }}>Done</Text>
              </Pressable>
            </View>
            <View style={{ flexDirection: "row", gap: 8, paddingHorizontal: 16, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: "#1C2438" }}>
              {nearSlots.map((slot) => (
                <Pressable key={slot} onPress={() => handleSelect(slot)}
                  style={{ flexDirection: "row", alignItems: "center", gap: 5, backgroundColor: value === slot ? "#1E3A5F" : "#1C2438", borderRadius: 10, paddingHorizontal: 12, paddingVertical: 7, borderWidth: 1, borderColor: value === slot ? "#3B82F6" : "#2D3748" }}>
                  <Zap size={12} color="#F59E0B" />
                  <Text style={{ fontFamily: "DMSans_700Bold", fontSize: 14, color: value === slot ? "#3B82F6" : "#FFFFFF" }}>{slot}</Text>
                </Pressable>
              ))}
            </View>
            <FlatList ref={listRef} data={ALL_SLOTS} keyExtractor={(item) => item} showsVerticalScrollIndicator={false}
              initialNumToRender={20} onScrollToIndexFailed={() => {}} contentContainerStyle={{ paddingBottom: 40 }}
              renderItem={({ item }) => {
                const isSelected = item === value;
                return (
                  <Pressable onPress={() => handleSelect(item)}
                    style={({ pressed }) => ({ paddingVertical: 13, paddingHorizontal: 20, backgroundColor: isSelected ? "#1E3A5F" : pressed ? "#1C2438" : "transparent", borderLeftWidth: isSelected ? 3 : 0, borderLeftColor: "#3B82F6" })}>
                    <Text style={{ fontFamily: isSelected ? "DMSans_700Bold" : "DMSans_400Regular", fontSize: 17, color: isSelected ? "#3B82F6" : "#D1D5DB", textAlign: "center" }}>{item}</Text>
                  </Pressable>
                );
              }}
            />
          </View>
        </View>
      </Modal>
    </View>
  );
}
