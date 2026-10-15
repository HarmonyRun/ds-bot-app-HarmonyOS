import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  ActionEnvelope,
  ApprovalList,
  ConversationList,
  DeviceList,
  EmptyPayload,
  ErrorPayload,
  MessagePage,
  PairCompletePayload,
  PairPayload,
  PairingStart,
  RefreshPayload,
  ServerInfo,
  Session,
  Submission,
  SubmissionReceipt,
  Target,
  TeamState
} from '../model/Models';

export class MobileApiError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(message: string, statusCode: number = 0, code: string = 'request_failed') {
    super(message);
    this.name = 'MobileApiError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

function normalizedOrigin(value: string): string {
  const candidate = value.trim().replace(/\/+$/u, '');
  if (!candidate.startsWith('https://')) {
    throw new MobileApiError('服务器地址必须使用 HTTPS。', 0, 'insecure_url');
  }
  if (candidate.includes('?') || candidate.includes('#')) {
    throw new MobileApiError('服务器地址不能包含查询参数或片段。', 0, 'invalid_url');
  }
  const remainder = candidate.slice('https://'.length);
  const slash = remainder.indexOf('/');
  const authority = slash < 0 ? remainder : remainder.slice(0, slash);
  const path = slash < 0 ? '' : remainder.slice(slash);
  if (authority.length === 0 || authority.includes('@') || (path.length > 0 && path !== '/mobile/v1')) {
    throw new MobileApiError('服务器地址格式无效。', 0, 'invalid_url');
  }
  return `https://${authority}`;
}

function pinToBase64(value: string): string {
  if (!/^sha256:[a-f0-9]{64}$/u.test(value)) {
    throw new MobileApiError('配对码中的电脑身份指纹无效。', 0, 'invalid_tls_pin');
  }
  const hex = value.slice(7);
  const bytes = new Uint8Array(32);
  for (let index = 0; index < 32; index++) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return new util.Base64Helper().encodeToStringSync(bytes, util.Type.BASIC);
}

function responseText(result: string | object | ArrayBuffer): string {
  if (typeof result === 'string') return result;
  if (result instanceof ArrayBuffer) return '';
  return JSON.stringify(result);
}

export class MobileApi {
  private readonly origin: string;
  private readonly tlsPin: string;
  private session?: Session;
  private serverId?: string;
  private refreshing: boolean = false;

  constructor(serverUrl: string, tlsPin: string = '', session?: Session) {
    this.origin = normalizedOrigin(serverUrl);
    this.tlsPin = tlsPin;
    this.session = session;
    this.serverId = session?.serverId;
    if (session?.serverUrl !== undefined && normalizedOrigin(session.serverUrl) !== this.origin) {
      throw new MobileApiError('会话所属服务器地址已改变，请重新配对。', 0, 'server_changed');
    }
    if (session?.tlsPin !== undefined && session.tlsPin !== this.tlsPin) {
      throw new MobileApiError('电脑身份指纹已改变，请重新配对。', 0, 'server_changed');
    }
  }

  getSession(): Session | undefined {
    return this.session;
  }

  private async request<T>(path: string, method: http.RequestMethod = http.RequestMethod.GET,
    body?: object, authenticated: boolean = true, retry: boolean = true): Promise<T> {
    const client = http.createHttp();
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    };
    if (authenticated) {
      if (this.session === undefined) throw new MobileApiError('设备尚未配对。', 401, 'unauthorized');
      headers['Authorization'] = `Bearer ${this.session.accessToken}`;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      extraData: body === undefined ? undefined : JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: 15000,
      readTimeout: 45000,
      maxLimit: 20 * 1024 * 1024
    };
    if (this.tlsPin.length > 0) {
      options.remoteValidation = 'skip';
      options.certificatePinning = {
        publicKeyHash: pinToBase64(this.tlsPin),
        hashAlgorithm: 'SHA-256'
      };
    }
    try {
      const response = await client.request(`${this.origin}/mobile/v1${path}`, options);
      if ((response.responseCode === 401 || response.responseCode === 403) && authenticated && retry) {
        await this.refresh();
        return this.request<T>(path, method, body, authenticated, false);
      }
      const text = responseText(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        let failure: ErrorPayload = {};
        try { failure = JSON.parse(text) as ErrorPayload; } catch (_error) {}
        throw new MobileApiError(failure.message ?? failure.error ?? `请求失败（HTTP ${response.responseCode}）`,
          response.responseCode, failure.code ?? 'request_failed');
      }
      if (text.length === 0) return new EmptyPayload() as T;
      return JSON.parse(text) as T;
    } finally {
      client.destroy();
    }
  }

  private async refresh(): Promise<void> {
    if (this.refreshing) throw new MobileApiError('正在刷新会话，请稍后重试。', 401, 'refresh_busy');
    if (this.session === undefined) throw new MobileApiError('设备尚未配对。', 401, 'unauthorized');
    this.refreshing = true;
    try {
      const refreshPayload: RefreshPayload = { refreshToken: this.session.refreshToken };
      const refreshed = await this.request<Session>('/auth/refresh', http.RequestMethod.POST,
        refreshPayload, false, false);
      if (refreshed.serverId !== this.session.serverId) {
        throw new MobileApiError('服务器身份已改变，请重新配对。', 401, 'server_changed');
      }
      refreshed.serverUrl = this.origin;
      refreshed.tlsPin = this.tlsPin;
      this.session = refreshed;
    } finally {
      this.refreshing = false;
    }
  }

  async info(): Promise<ServerInfo> {
    const info = await this.request<ServerInfo>('/info', http.RequestMethod.GET, undefined, false);
    if (info.protocolVersion !== 1) {
      throw new MobileApiError('应用与主机的移动协议版本不一致，请同时更新。', 0, 'incompatible_protocol');
    }
    if (typeof info.serverId !== 'string' || info.serverId.length === 0) {
      throw new MobileApiError('服务器未返回有效身份。', 0, 'invalid_server');
    }
    if (this.serverId !== undefined && this.serverId !== info.serverId) {
      throw new MobileApiError('服务器身份已改变，请重新配对。', 0, 'server_changed');
    }
    this.serverId = info.serverId;
    return info;
  }

  pair(code: string, deviceName: string): Promise<PairingStart> {
    const payload: PairPayload = { code: code, deviceName: deviceName };
    return this.request<PairingStart>('/pairings', http.RequestMethod.POST, payload, false);
  }

  async completePairing(claimToken: string): Promise<Session | undefined> {
    if (this.serverId === undefined) await this.info();
    const payload: PairCompletePayload = { claimToken: claimToken };
    const result = await this.request<object>('/pairings/complete', http.RequestMethod.POST, payload, false);
    const session = result as Session;
    if (typeof session.accessToken !== 'string') return undefined;
    if (session.serverId !== this.serverId) {
      throw new MobileApiError('配对响应来自另一台服务器，请重新配对。', 0, 'server_changed');
    }
    session.serverUrl = this.origin;
    session.tlsPin = this.tlsPin;
    this.session = session;
    return session;
  }

  state(): Promise<TeamState> {
    return this.request<TeamState>('/state');
  }

  conversations(): Promise<ConversationList> {
    return this.request<ConversationList>('/conversations');
  }

  messages(conversationId: string, limit: number = 80): Promise<MessagePage> {
    return this.request<MessagePage>(`/conversations/${encodeURIComponent(conversationId)}/messages?limit=${limit}`);
  }

  target(conversationId: string): Promise<Target> {
    return this.request<Target>(`/conversations/${encodeURIComponent(conversationId)}/target`);
  }

  submit(submission: Submission): Promise<SubmissionReceipt> {
    return this.request<SubmissionReceipt>('/submissions', http.RequestMethod.POST, submission);
  }

  cancel(conversationId: string): Promise<object> {
    return this.request<object>(`/conversations/${encodeURIComponent(conversationId)}/cancel`,
      http.RequestMethod.POST, new EmptyPayload());
  }

  action<T>(endpoint: string, payload: object = new EmptyPayload()): Promise<T> {
    const body: ActionEnvelope = { endpoint: endpoint, payload: payload };
    return this.request<T>('/actions', http.RequestMethod.POST, body);
  }

  approvals(): Promise<ApprovalList> {
    return this.action<ApprovalList>('approvals');
  }

  devices(): Promise<DeviceList> {
    return this.request<DeviceList>('/devices');
  }
}
