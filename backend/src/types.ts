export type DemoRole = 'sensor' | 'caregiver';

export type AlertState = 'new' | 'acknowledged' | 'escalated';

export type AlertPriority = 'high' | 'medium';

export type CVEventType =
  | 'bed_exit_risk'
  | 'person_detected'
  | 'motion_spike'
  | 'no_motion'
  | 'upright_pose_detected';

export type TimelineKind =
  | 'alert_created'
  | 'alert_acknowledged'
  | 'alert_escalated';

export interface DemoSession {
  id: string;
  token: string;
  displayName: string;
  role: DemoRole;
  createdAt: string;
}

export interface CVEvent {
  id: string;
  idempotencyKey: string;
  roomId: string;
  deviceId: string;
  eventType: CVEventType;
  confidence: number;
  occurredAt: string;
  metadata: Record<string, unknown>;
}

export interface OverlayPoint {
  x: number;
  y: number;
}

export interface OverlayRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface OverlaySegment {
  from: OverlayPoint;
  to: OverlayPoint;
  confidence: number;
}

export interface MotionOverlayFrame {
  updatedAt: string;
  personDetected: boolean;
  poseLabel: string;
  motionScore: number;
  personBox?: OverlayRect | null;
  trail: OverlayPoint[];
  skeleton: OverlaySegment[];
}

export interface MotionOverlayPayload {
  roomId: string;
  deviceId: string;
  overlay: MotionOverlayFrame;
}

export interface Alert {
  id: string;
  roomId: string;
  deviceId: string;
  eventType: CVEventType;
  title: string;
  body: string;
  priority: AlertPriority;
  state: AlertState;
  createdAt: string;
  updatedAt: string;
  sourceEventId: string;
}

export interface TimelineEntry {
  id: string;
  kind: TimelineKind;
  roomId: string;
  alertId: string;
  createdAt: string;
  summary: string;
}

export interface RealtimeEvent {
  event:
    | 'alert.created'
    | 'alert.updated'
    | 'timeline.created'
    | 'overlay.updated';
  data: unknown;
}
