export interface PairingCode {
  url: string;
  code: string;
  serverId: string;
  tlsPin?: string;
}

export interface ServerInfo {
  protocolVersion: number;
  serverId: string;
  name?: string;
}

export interface PairingStart {
  claimToken: string;
  requestId: string;
  status: string;
}

export interface Session {
  accessToken: string;
  refreshToken: string;
  deviceId: string;
  serverId: string;
  expiresAt: number | string;
  serverUrl?: string;
  tlsPin?: string;
}

export interface ClientProfile {
  serverUrl: string;
  serverName: string;
  tlsPin: string;
  session: Session;
}

export interface Avatar {
  shape?: string;
  image?: string;
  color?: string;
}

export interface Bot {
  id: string;
  name: string;
  role?: string;
  color?: string;
  instructions?: string;
  model?: string;
  sessionId?: string;
  waiting?: boolean;
  avatar?: Avatar;
  workDir?: string;
  pinned?: boolean;
  hidden?: boolean;
}

export interface Room {
  id: string;
  name: string;
  members: string[];
  admin?: string;
  notice?: string;
  pinned?: boolean;
  hidden?: boolean;
}

export interface ModelOption {
  ref: string;
  name: string;
  providerName?: string;
}

export interface TeamState {
  bots: Bot[];
  rooms: Room[];
  models: ModelOption[];
  mainBotId?: string;
  mainBotIds?: string[];
  readOnly?: string;
}

export interface Conversation {
  id: string;
  kind: string;
  name: string;
  role?: string;
  sessionId: string;
  waiting?: string;
  pinned?: boolean;
  hidden?: boolean;
  updatedAt?: number | string;
}

export interface ConversationList {
  conversations: Conversation[];
}

export interface ToolActivity {
  durationMs?: number;
  callId: string;
  name: string;
  state: string;
  input?: string;
  output?: string;
  isError?: boolean;
  truncated?: boolean;
}

export interface Message {
  id: string;
  sessionId: string;
  seq: number;
  role: string;
  text: string;
  createdAt: number | string;
  reasoning?: string;
  interrupted?: boolean;
  pending?: boolean;
  tool?: ToolActivity;
}

export interface MessagePage {
  messages: Message[];
  cursor?: string;
  sessionId: string;
}

export interface Target {
  conversationId: string;
  sessionId: string;
  revision: string | number;
}

export interface Submission {
  conversationId: string;
  sessionId: string;
  requestId: string;
  text: string;
}

export interface SubmissionReceipt {
  requestId: string;
  status: string;
  conversationId?: string;
  sessionId?: string;
}

export interface ActionEnvelope {
  endpoint: string;
  payload: object;
}

export interface ErrorPayload {
  error?: string;
  message?: string;
  code?: string;
}

export class EmptyPayload {}

export interface RefreshPayload {
  refreshToken: string;
}

export interface PairPayload {
  code: string;
  deviceName: string;
}

export interface PairCompletePayload {
  claimToken: string;
}

export interface ApprovalDecisionPayload {
  id: string;
  decision: string;
}

export interface DeviceListItem {
  id: string;
  name?: string;
  deviceName?: string;
}

export interface DeviceList {
  devices: DeviceListItem[];
}

export interface Approval {
  id: string;
  conversationId: string;
  sessionId: string;
  toolName: string;
  reason?: string;
}

export interface ApprovalList {
  requests: Approval[];
}
