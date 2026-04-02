import { Tabs } from "expo-router";
import { View, Text } from "react-native";
import { Clock, Calendar, History, User } from "lucide-react-native";

function TabIcon({
  icon: Icon, color, focused, label,
}: {
  icon: React.ComponentType<{ size: number; color: string; strokeWidth: number }>;
  color: string; focused: boolean; label: string;
}) {
  return (
    <View style={{ alignItems: "center", paddingTop: 8 }}>
      <Icon size={22} color={color} strokeWidth={focused ? 2.5 : 1.5} />
      <Text style={{
        fontSize: 10, marginTop: 3, color: color,
        fontFamily: focused ? "DMSans_700Bold" : "DMSans_400Regular",
      }}>
        {label}
      </Text>
    </View>
  );
}

export default function AppLayout() {
  return (
    <Tabs screenOptions={{
      headerShown: false,
      tabBarStyle: {
        backgroundColor: "#111827", borderTopColor: "#1C2438",
        borderTopWidth: 1, height: 80, paddingBottom: 16,
      },
      tabBarActiveTintColor: "#3B82F6",
      tabBarInactiveTintColor: "#4B5563",
      tabBarShowLabel: false,
    }}>
      <Tabs.Screen name="index" options={{
        tabBarIcon: ({ color, focused }) => <TabIcon icon={Clock} color={color} focused={focused} label="Today" />,
      }} />
      <Tabs.Screen name="leave" options={{
        tabBarIcon: ({ color, focused }) => <TabIcon icon={Calendar} color={color} focused={focused} label="Leave" />,
      }} />
      <Tabs.Screen name="history" options={{
        tabBarIcon: ({ color, focused }) => <TabIcon icon={History} color={color} focused={focused} label="History" />,
      }} />
      <Tabs.Screen name="profile" options={{
        tabBarIcon: ({ color, focused }) => <TabIcon icon={User} color={color} focused={focused} label="Profile" />,
      }} />
    </Tabs>
  );
}
