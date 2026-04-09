import { randomUUID } from 'node:crypto';

import type {
  Alert,
  AlertState,
  CVEvent,
  DemoRole,
  DemoSession,
  MotionOverlayPayload,
  RealtimeEvent,
  TimelineEntry,
} from './types.js';

interface CreateSessionInput {
  displayName: string;
  role: DemoRole;
}

interface CreateCVEventInput {
  idempotencyKey: string;
  roomId: string;
  deviceId: string;
  eventType: CVEvent['eventType'];
  confidence: number;
  occurredAt: string;
  metadata: Record<string, unknown>;
}

interface AlertUpdateInput {
  id: string;
  nextState: Extract<AlertState, 'acknowledged' | 'escalated'>;
  actorName: string;
  reason?: string;
}

interface Subscriber {
  id: string;
  send: (event: RealtimeEvent) => void;
}

const ALERT_COPY: Record<CVEvent['eventType'], { title: string; body: string }> = {
  bed_exit_risk: {
    title: 'Bed Exit Risk',
    body: 'Movement detected in bedside exit zone. Open live view now.',
  },
  person_detected: {
    title: 'Person Detected',
    body: 'A person was detected in the room.',
  },
  motion_spike: {
    title: 'Motion Spike',
    body: 'Significant motion was detected in the room.',
  },
  no_motion: {
    title: 'No Motion',
    body: 'No motion was detected for the configured threshold.',
  },
  upright_pose_detected: {
    title: 'Upright Pose Detected',
    body: 'An upright pose was detected near the monitored zone.',
  },
};

export class InMemoryStore {
  private readonly sessions = new Map<string, DemoSession>();
  private readonly sessionsByToken = new Map<string, DemoSession>();
  private readonly cvEventsByIdempotencyKey = new Map<string, CVEvent>();
  private readonly alerts = new Map<string, Alert>();
  private readonly timeline: TimelineEntry[] = [];
  private readonly subscribers = new Map<string, Subscriber>();

  createSession(input: CreateSessionInput) {
    const session: DemoSession = {
      id: `sess_${randomUUID()}`,
      token: `demo_${randomUUID()}`,
      displayName: input.displayName,
      role: input.role,
      createdAt: new Date().toISOString(),
    };

    this.sessions.set(session.id, session);
    this.sessionsByToken.set(session.token, session);
    return session;
  }

  getSessionByToken(token: string | undefined) {
    if (!token) return undefined;
    return this.sessionsByToken.get(token);
  }

  listAlerts(roomId?: string, state?: Alert['state']) {
    return [...this.alerts.values()]
      .filter((alert) => (roomId ? alert.roomId === roomId : true))
      .filter((alert) => (state ? alert.state === state : true))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  listTimeline(roomId?: string) {
    return [...this.timeline]
      .filter((entry) => (roomId ? entry.roomId === roomId : true))
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  addSubscriber(send: Subscriber['send']) {
    const subscriber: Subscriber = {
      id: randomUUID(),
      send,
    };
    this.subscribers.set(subscriber.id, subscriber);
    return subscriber.id;
  }

  removeSubscriber(id: string) {
    this.subscribers.delete(id);
  }

  updateMotionOverlay(input: MotionOverlayPayload) {
    this.broadcast({ event: 'overlay.updated', data: input });
    return input;
  }

  createOrGetCVEvent(input: CreateCVEventInput) {
    const existing = this.cvEventsByIdempotencyKey.get(input.idempotencyKey);
    if (existing) {
      const existingAlert = [...this.alerts.values()].find(
        (alert) => alert.sourceEventId === existing.id,
      );
      return {
        accepted: false,
        event: existing,
        alert: existingAlert,
      };
    }

    const event: CVEvent = {
      id: `cve_${randomUUID()}`,
      ...input,
    };
    this.cvEventsByIdempotencyKey.set(input.idempotencyKey, event);

    const now = new Date().toISOString();
    const copy = ALERT_COPY[input.eventType];
    const alert: Alert = {
      id: `alert_${randomUUID()}`,
      roomId: input.roomId,
      deviceId: input.deviceId,
      eventType: input.eventType,
      title: copy.title,
      body: copy.body,
      priority: input.eventType === 'bed_exit_risk' ? 'high' : 'medium',
      state: 'new',
      createdAt: now,
      updatedAt: now,
      sourceEventId: event.id,
    };
    this.alerts.set(alert.id, alert);

    const timelineEntry: TimelineEntry = {
      id: `tl_${randomUUID()}`,
      kind: 'alert_created',
      roomId: alert.roomId,
      alertId: alert.id,
      createdAt: now,
      summary: `${alert.title} detected`,
    };
    this.timeline.push(timelineEntry);

    this.broadcast({ event: 'alert.created', data: alert });
    this.broadcast({ event: 'timeline.created', data: timelineEntry });

    return {
      accepted: true,
      event,
      alert,
    };
  }

  updateAlert(input: AlertUpdateInput) {
    const alert = this.alerts.get(input.id);
    if (!alert) return undefined;

    if (alert.state === input.nextState) {
      return alert;
    }

    if (alert.state === 'escalated') {
      return alert;
    }

    alert.state = input.nextState;
    alert.updatedAt = new Date().toISOString();

    const summary =
      input.nextState === 'acknowledged'
        ? `Alert acknowledged by ${input.actorName}`
        : `Alert escalated by ${input.actorName}${input.reason ? `: ${input.reason}` : ''}`;

    const timelineEntry: TimelineEntry = {
      id: `tl_${randomUUID()}`,
      kind:
        input.nextState === 'acknowledged'
          ? 'alert_acknowledged'
          : 'alert_escalated',
      roomId: alert.roomId,
      alertId: alert.id,
      createdAt: alert.updatedAt,
      summary,
    };
    this.timeline.push(timelineEntry);

    this.broadcast({ event: 'alert.updated', data: alert });
    this.broadcast({ event: 'timeline.created', data: timelineEntry });

    return alert;
  }

  private broadcast(event: RealtimeEvent) {
    for (const subscriber of this.subscribers.values()) {
      subscriber.send(event);
    }
  }
}
