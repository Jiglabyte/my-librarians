export interface TimesheetEntry {
  id: string;
  userId: string;
  date: string;
  timeIn?: string | null;
  timeOut?: string | null;
  clockInMethod?: string | null;
  clockOutMethod?: string | null;
  status: string;
  comment?: string | null;
  locationIn?: string | null;
  locationOut?: string | null;
  totalHours?: number | null;
  isOffsite: boolean;
  projectName?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface LeaveRequest {
  id: string;
  userId: string;
  leaveType: string;
  startDate: string;
  endDate: string;
  status: string;
  comment?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface UserProfile {
  id: string;
  name: string;
  email: string;
  department?: string | null;
  employeeId?: string | null;
  image?: string | null;
}

export interface LocationSettings {
  id: string;
  userId: string;
  latitude?: number | null;
  longitude?: number | null;
  radius: number;
  address?: string | null;
  enabled: boolean;
  createdAt: string;
  updatedAt: string;
}
