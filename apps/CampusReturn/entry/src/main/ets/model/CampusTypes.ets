export interface UserProfile { id: string; name: string; role: string; credit: number; false_claims: number; banned: boolean; creditFloor: number; }
export interface CampusItem {
  itemId: string; kind: string; category: string; color: string; place: string; occurredAt: number;
  description: string; ocrText: string; imageBase64: string; question: string; ownerId: string;
  ownerName: string; state: string; version: number; ocrHint: string; imagePrivate: boolean; completedMatchId: string;
}
export interface PublishPayload {
  itemId: string; kind: string; category: string; color: string; place: string; occurredAt: number;
  description: string; ocrText: string; imageBase64: string; question: string; answer: string;
}
export interface UploadAck { itemId: string; status: string; }
export interface OutboxEntry { itemId: string; payload: PublishPayload; attempts: number; retryAt: number; error: string; }
export interface SyncPage { items: CampusItem[]; cursor: number; hasMore: boolean; }
export interface Policy {
  weights: Weights; threshold: number; windowHours: number; matchHours: number; appealHours: number;
  creditFloor: number; banCount: number; credit: CreditPolicy;
}
export interface Weights { place: number; time: number; ocr: number; text: number; color: number; }
export interface CreditPolicy { complete: number; no_show: number; false_post: number; false_claim: number; malicious_appeal: number; }
export interface Candidate { item: CampusItem; eligible: boolean; score: number; factors: Weights; automatic: boolean; }
export interface CandidatePage { candidates: Candidate[]; policy: Policy; }
export interface TimelineEvent { seq: number; match_id: string; actor: string; state: string; message: string; created: number; }
export interface ClaimRow { claimId: string; userId: string; name: string; state: string; score: number; level: number; answer: string; evidenceText: string; evidenceImage: string; credit: number; }
export interface PairCase { matchId: string; lostId: string; foundId: string; foundOwner: string; lostOwner: string; state: string; score: number; category: string; place: string; question: string; deadline: number; claims: ClaimRow[]; events: TimelineEvent[]; }
export interface CasesPage { matches: PairCase[]; }
export interface AppealRow { appealId: string; matchId: string; userId: string; level: number; evidenceText: string; evidenceImage: string; state: string; decision: string; deadline: number; }
export interface AppealsPage { appeals: AppealRow[]; }
export interface NotificationRow { id: number; user_id: string; message: string; created: number; }
export interface NotificationsPage { notifications: NotificationRow[]; }
export interface NameCount { name: string; count: number; }
export interface PlatformStats { users: number; items: number; matches: number; pendingAppeals: number; completed: number; }
export interface LedgerRow { id: number; user_id: string; kind: string; delta: number; reason_id: string; actor: string; created: number; }
export interface AdminPage { stats: PlatformStats; categories: NameCount[]; users: UserProfile[]; violations: LedgerRow[]; policy: Policy; }
export interface ActionResult { state?: string; message?: string; claimId?: string; matchId?: string; winner?: string; decision?: string; appealId?: string; }
export interface PairInput { lostId: string; foundId: string; }
export interface AnswerInput { answer: string; level: number; evidenceText: string; evidenceImage: string; }
export interface AppealInput { lostId: string; level: number; evidenceText: string; evidenceImage: string; }
export interface ReviewInput { passed: boolean; score: number; }
export interface DecisionInput { valid: boolean; }
export interface ViolationInput { userId: string; kind: string; reasonId: string; }
export interface StructuredFields { category: string; color: string; place: string; timeText: string; words: string[]; note: string; }
export interface PhotoAnalysis { category: string; ocrText: string; note: string; }
export const CATEGORIES: string[] = ['校园卡', '证件', '书籍', '雨伞', '水杯', '钥匙', '手机', '电脑', '背包', '耳机', '其它'];
export const DEFAULT_POLICY: Policy = { weights: { place: .30, time: .20, ocr: .25, text: .20, color: .05 }, threshold: .62,
  windowHours: 168, matchHours: 48, appealHours: 48, creditFloor: 60, banCount: 2,
  credit: { complete: 5, no_show: -10, false_post: -15, false_claim: -40, malicious_appeal: -20 } };
