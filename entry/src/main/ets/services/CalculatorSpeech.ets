import { textToSpeech } from '@kit.CoreSpeechKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** Public state used by the calculator page to render the speech toggle. */
export class SpeechStatus {
  ready: boolean = false;
  speaking: boolean = false;
  message: string = '语音准备中';
}

type StatusHandler = (status: SpeechStatus) => void;

/**
 * Small lifecycle-safe text-to-speech service for calculator feedback.
 *
 * Text is queued in this class and submitted one item at a time. This keeps
 * fast key presses ordered while still allowing stop() to cancel everything.
 * The Core Speech engine is configured for the local Chinese voice (online=1
 * in the HarmonyOS API: 0 is online and 1 is offline).
 */
export class CalculatorSpeech {
  private static readonly LOG_DOMAIN: number = 0x1415;
  private static readonly MAX_QUEUE: number = 32;
  private static readonly MAX_PENDING_CHARACTERS: number = 4096;
  private readonly onStatus: StatusHandler;
  private engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private queue: string[] = [];
  private requestSerial: number = 0;
  private currentRequest: string = '';
  private createPromise: Promise<void> | undefined = undefined;
  private enabled: boolean = true;
  private disposed: boolean = false;
  private status: SpeechStatus = new SpeechStatus();

  constructor(onStatus: StatusHandler) {
    this.onStatus = onStatus;
    this.publish();
  }

  /** Create the native engine once. A late callback is shut down after dispose. */
  async initialize(): Promise<void> {
    if (this.disposed || !this.enabled) return;
    if (this.engine !== undefined) {
      this.updateStatus(true, this.status.speaking, '语音已就绪');
      return;
    }
    if (this.createPromise !== undefined) {
      return this.createPromise;
    }
    this.updateStatus(false, false, '语音准备中');
    this.createPromise = this.createEngine().then(() => {
      this.createPromise = undefined;
    }, () => {
      this.createPromise = undefined;
    });
    return this.createPromise;
  }

  /** Add one short, non-sensitive calculator phrase to the FIFO. */
  speak(text: string): void {
    if (this.disposed || !this.enabled) return;
    const phrase: string = text.trim();
    if (phrase.length === 0) return;
    let pendingCharacters: number = phrase.length;
    this.queue.forEach((item: string) => { pendingCharacters += item.length + 1; });
    if (pendingCharacters > CalculatorSpeech.MAX_PENDING_CHARACTERS) {
      // Preserve all accepted input. Report overload rather than silently
      // discarding earlier keys or permitting unbounded queued speech.
      this.updateStatus(this.engine !== undefined, this.status.speaking, '按键过快，语音队列已满，请稍候');
      return;
    }
    if (this.queue.length >= CalculatorSpeech.MAX_QUEUE) {
      const last: number = this.queue.length - 1;
      this.queue[last] = `${this.queue[last]}，${phrase}`;
    } else {
      this.queue.push(phrase);
    }
    if (this.engine === undefined) {
      void this.initialize();
      return;
    }
    this.pump();
  }

  setEnabled(enabled: boolean): void {
    if (this.disposed) return;
    if (this.enabled === enabled) {
      // Calling setEnabled(true) from a page's onPageShow should also recover
      // from an engine that has not finished (or failed) initialization.
      if (enabled && this.engine === undefined) void this.initialize();
      return;
    }
    this.enabled = enabled;
    if (!enabled) {
      this.stop();
      this.updateStatus(this.engine !== undefined, false, '语音已关闭');
      return;
    }
    this.updateStatus(this.engine !== undefined, false, this.engine === undefined ? '语音准备中' : '语音已就绪');
    if (this.engine === undefined) void this.initialize();
    else this.pump();
  }

  /** Stop current playback and clear pending key/result phrases immediately. */
  stop(): void {
    if (this.disposed) return;
    this.queue = [];
    this.currentRequest = '';
    if (this.engine !== undefined) {
      try {
        this.engine.stop();
      } catch (error) {
        this.logFailure('stop', error as BusinessError);
        this.releaseEngine();
      }
    }
    this.updateStatus(this.engine !== undefined, false,
      !this.enabled ? '语音已关闭' : (this.engine !== undefined ? '语音已就绪' : '语音未就绪，点击重试'));
  }

  /** Stop and release native resources. Safe to call repeatedly. */
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.enabled = false;
    this.queue = [];
    this.currentRequest = '';
    this.releaseEngine();
  }

  private async createEngine(): Promise<void> {
    let createdEngine: textToSpeech.TextToSpeechEngine | undefined = undefined;
    try {
      const nativeEngine: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine({
        language: 'zh-CN',
        person: 0,
        online: 1,
        extraParams: { 'locate': 'CN', 'style': 'interaction-broadcast' }
      });
      createdEngine = nativeEngine;
      if (this.disposed || !this.enabled) {
        try {
          nativeEngine.shutdown();
        } catch (error) {
          this.logFailure('late shutdown', error as BusinessError);
        }
        return;
      }
      this.engine = nativeEngine;
      nativeEngine.setListener({
        onStart: (requestId: string, response: textToSpeech.StartResponse): void => {
          if (this.disposed || !this.enabled || this.engine !== nativeEngine || requestId !== this.currentRequest) return;
          hilog.info(CalculatorSpeech.LOG_DOMAIN, 'CalculatorSpeech', 'onStart request=%{public}s', requestId);
          this.updateStatus(true, true, '正在播报');
        },
        onComplete: (requestId: string, response: textToSpeech.CompleteResponse): void => {
          if (this.disposed || !this.enabled || this.engine !== nativeEngine || requestId !== this.currentRequest) return;
          // type=0 means synthesis complete; type=1 means audio playback complete.
          hilog.info(CalculatorSpeech.LOG_DOMAIN, 'CalculatorSpeech', 'onComplete request=%{public}s type=%{public}d', requestId, response.type);
          if (response.type === 1) {
            this.currentRequest = '';
            this.updateStatus(true, false, '语音已就绪');
            this.pump();
          }
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse): void => {
          hilog.info(CalculatorSpeech.LOG_DOMAIN, 'CalculatorSpeech', 'onStop request=%{public}s', requestId);
          if (this.disposed || this.engine !== nativeEngine) return;
          if (requestId === this.currentRequest) {
            this.currentRequest = '';
            this.updateStatus(this.engine !== undefined, false, this.enabled ? '语音已就绪' : '语音已关闭');
          }
        },
        onError: (requestId: string, errorCode: number, errorMessage: string): void => {
          hilog.error(CalculatorSpeech.LOG_DOMAIN, 'CalculatorSpeech', 'onError request=%{public}s code=%{public}d', requestId, errorCode);
          if (this.disposed || this.engine !== nativeEngine || requestId !== this.currentRequest) return;
          this.failSpeech('语音播报失败，点击重试');
        }
      });
      // onData is optional in API 24. Native playback is used, so no synthesized
      // audio buffers or microphone permissions are needed.
      if (this.disposed || !this.enabled || this.engine !== nativeEngine) return;
      this.updateStatus(true, false, '语音已就绪');
      this.pump();
    } catch (error) {
      this.logFailure('createEngine', error as BusinessError);
      if (createdEngine !== undefined && this.engine === createdEngine) this.releaseEngine();
      this.queue = [];
      if (!this.disposed && this.enabled) this.updateStatus(false, false, '语音不可用，点击重试');
    }
  }

  private pump(): void {
    if (this.disposed || !this.enabled || this.engine === undefined || this.currentRequest !== '' || this.queue.length === 0) return;
    const phrase: string | undefined = this.queue.shift();
    if (phrase === undefined) return;
    const requestId: string = `calculator-${this.requestSerial++}`;
    this.currentRequest = requestId;
    try {
      this.engine.speak(phrase, {
        requestId,
        // 0 is the platform FIFO mode; this service submits one item at a time.
        extraParams: { 'queueMode': 0, 'speed': 1, 'volume': 1, 'pitch': 1, 'languageContext': 'zh-CN' }
      });
    } catch (error) {
      this.logFailure('speak', error as BusinessError);
      this.failSpeech('语音播报失败，点击重试');
    }
  }

  private failSpeech(message: string): void {
    this.queue = [];
    this.currentRequest = '';
    this.releaseEngine();
    this.updateStatus(false, false, this.enabled ? message : '语音已关闭');
  }

  private releaseEngine(): void {
    const nativeEngine: textToSpeech.TextToSpeechEngine | undefined = this.engine;
    // Invalidate first: stop/shutdown can themselves invoke callbacks.
    this.engine = undefined;
    if (nativeEngine === undefined) return;
    try {
      nativeEngine.stop();
    } catch (error) {
      this.logFailure('release stop', error as BusinessError);
    }
    try {
      nativeEngine.shutdown();
    } catch (error) {
      this.logFailure('shutdown', error as BusinessError);
    }
  }

  private logFailure(action: string, error: BusinessError): void {
    hilog.error(CalculatorSpeech.LOG_DOMAIN, 'CalculatorSpeech', '%{public}s failed code=%{public}d', action, error.code || -1);
  }

  private updateStatus(ready: boolean, speaking: boolean, message: string): void {
    this.status.ready = ready;
    this.status.speaking = speaking;
    this.status.message = message;
    this.publish();
  }

  private publish(): void {
    if (this.disposed) return;
    try {
      this.onStatus({ ready: this.status.ready, speaking: this.status.speaking, message: this.status.message });
    } catch (error) {
      // A page can disappear between an async callback and the UI update.
    }
  }
}
