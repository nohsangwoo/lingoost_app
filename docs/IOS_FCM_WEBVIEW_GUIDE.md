## iOS FCM + WebView 연동 가이드 (코드 중심, 바로 적용 가능한 버전)

이 문서는 Flutter(iOS) 앱 + Web(Next.js) 조합에서 FCM을 즉시 동작시키기 위한 “코드 레벨” 구현 지침입니다. 그대로 붙여 넣고 환경변수만 설정하면 동작하도록 구성했습니다.

### 0. 요구사항 체크
- Firebase 프로젝트, iOS 앱 등록, GoogleService-Info.plist(Runner 포함)
- Apple Developer의 APNs 키(.p8) → Firebase 콘솔에 업로드(개/배포 둘 다)
- iOS Minimum Deployment Target: 15.0 이상

---

### 1) iOS/Flutter 프로젝트 설정

#### 1-1. Podfile (iOS)
```ruby
# ios/Podfile
platform :ios, '15.0'

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
```

#### 1-2. pubspec.yaml 의존성(예시)
```yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.10
  flutter_local_notifications: ^16.3.2
  flutter_inappwebview: ^6.0.0 # 또는 webview_flutter
  supabase_flutter: ^2.10.1 # 프로젝트에 맞게
```

#### 1-3. main.dart (Firebase 초기화 + 백그라운드 핸들러)
```dart
// lib/main.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart'; // 없으면 iOS는 기본 initializeApp() 사용
import 'screens/webview_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    if (Platform.isIOS) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  }
  // 필요시 백그라운드 처리
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Firebase.apps.isEmpty) {
    if (Platform.isIOS) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  }
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WebViewScreen(),
  ));
}
```

#### 1-4. FcmService (권한/포그라운드 배너/로컬 알림)
```dart
// lib/services/fcm_service.dart (핵심 부분만)
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'dart:io';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  String? _currentToken;

  Future<void> initialize({
    Function(String)? onTokenRefresh,
    Function(Map<String, dynamic>)? onMessageReceived,
    Function(Map<String, dynamic>)? onNotificationTapped,
  }) async {
    await _requestPermission();
    await _initializeLocalNotifications();

    // iOS 포그라운드에서도 시스템 배너 표시
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );

    await _getToken();
    _messaging.onTokenRefresh.listen((t) { _currentToken = t; onTokenRefresh?.call(t); });

    FirebaseMessaging.onMessage.listen((msg) async {
      onMessageReceived?.call({
        'title': msg.notification?.title,
        'body': msg.notification?.body,
        'data': msg.data,
      });
      // iOS는 시스템 배너가 이미 표시됨. 중복 방지 위해 로컬 알림은 기본 사용 안 함.
      // 필요 시 msg.data['showForeground'] == 'true' 조건으로 로컬 알림 표시 가능.
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      onNotificationTapped?.call({
        'title': msg.notification?.title,
        'body': msg.notification?.body,
        'data': msg.data,
      });
    });
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(const InitializationSettings(android: android, iOS: ios));
  }

  Future<String?> _getToken() async {
    _currentToken = await _messaging.getToken();
    return _currentToken;
  }

  String? get currentToken => _currentToken;
  Future<void> subscribeToTopic(String t) => _messaging.subscribeToTopic(t);
}
```

#### 1-5. WebView와 브릿지 (Flutter→Web JS 메시지)
핵심: 앱에서 토큰을 웹으로 전달하고, 웹은 이를 서버에 저장.

```dart
// lib/screens/webview_screen.dart (핵심만)
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/fcm_service.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});
  @override State<WebViewScreen> createState() => _S();
}

class _S extends State<WebViewScreen> {
  InAppWebViewController? _c;
  final _fcm = FcmService();

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://your-web-domain.com')),
      onWebViewCreated: (controller) async {
        _c = controller;
        // 토픽 제어 핸들러(선택)
        _c!.addJavaScriptHandler(handlerName: 'subscribeToTopic', callback: (args) async {
          await _fcm.subscribeToTopic(args.first as String);
          return {'success': true};
        });
      },
      onLoadStop: (controller, url) async {
        await _fcm.initialize(onTokenRefresh: (token) async {
          await _c?.evaluateJavascript(source: '''
            window.__fcmToken = "${_fcm.currentToken ?? ''}";
            window.dispatchEvent(new CustomEvent('fcmTokenReady', { detail: { token: '${_fcm.currentToken ?? ''}', platform: 'ios' }}));
            if (window.handleFlutterMessage) {
              window.handleFlutterMessage('FCM_TOKEN_RECEIVED', { token: '${_fcm.currentToken ?? ''}' });
              window.handleFlutterMessage('FCM_TOKEN_SAVE_REQUEST', { token: '${_fcm.currentToken ?? ''}', platform: 'ios', userId: null, deviceId: 'webview_device' });
            }
          ''');
        });
        // 앱 시작 시 브로드캐스트 자동 구독(선택)
        await _fcm.subscribeToTopic('broadcast');
      },
    );
  }
}
```

---

### 2) Web(Next.js) - 브릿지 훅 + 전역 마운트

#### 2-1. useWebViewBridge 훅(핵심 아이디어)
- window.handleFlutterMessage(type, data)을 수신
- 토큰 저장 요청 시 `/api/fcm/token` POST

```ts
// hooks/useWebViewBridge.ts (핵심만)
'use client'
export function useWebViewBridge() {
  // Flutter→Web 메시지 수신 함수 등록
  (window as any).handleFlutterMessage = (type: string, data: any) => {
    if (type === 'FCM_TOKEN_SAVE_REQUEST') {
      fetch('/api/fcm/token', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data),
      }).catch(console.error)
    }
  }
}
```

#### 2-2. 전역 마운트 컴포넌트
```tsx
// components/webview-bridge-initializer.tsx
'use client'
import { useWebViewBridge } from '@/hooks/useWebViewBridge'
export function WebViewBridgeInitializer() { useWebViewBridge(); return null }
```

#### 2-3. app/layout.tsx에 추가
```tsx
// app/layout.tsx
import { WebViewBridgeInitializer } from '@/components/webview-bridge-initializer'
...
<AuthStoreInitializer />
<WebViewBridgeInitializer />
<ThemeProvider ...>
```

---

### 3) 서버(Next.js API) & Firebase Admin

#### 3-1. 환경변수(4가지 방식 중 하나만 설정)
- FIREBASE_SERVICE_ACCOUNT_JSON: 서비스 계정 JSON 원문
- FIREBASE_SERVICE_ACCOUNT_BASE64: 위 JSON의 base64(한 줄)
- FIREBASE_SERVICE_ACCOUNT_PATH: 서버의 JSON 파일 경로
- 또는 개별 값 3개 조합:
  - FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY(\n 이스케이프)

#### 3-2. Firebase Admin 유틸
```ts
// lib/firebase-admin.ts
import * as admin from 'firebase-admin'

export function getFirebaseAdmin(): admin.app.App | null {
  try {
    if (admin.apps.length > 0) return admin.app()

    const jsonRaw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON
    const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64
    const path = process.env.FIREBASE_SERVICE_ACCOUNT_PATH
    const projectId = process.env.FIREBASE_PROJECT_ID
    const clientEmail = process.env.FIREBASE_CLIENT_EMAIL
    let privateKey = process.env.FIREBASE_PRIVATE_KEY

    let svc: admin.ServiceAccount | null = null
    if (jsonRaw) svc = JSON.parse(jsonRaw)
    else if (b64) svc = JSON.parse(Buffer.from(b64, 'base64').toString('utf-8'))
    else if (path) svc = require(path)
    else if (projectId && clientEmail && privateKey) {
      privateKey = privateKey!.replace(/\\n/g, '\n')
      svc = { projectId, clientEmail, privateKey } as any
    }
    if (!svc) { console.error('[FCM] Missing service account'); return null }

    return admin.initializeApp({ credential: admin.credential.cert(svc) })
  } catch (e) { console.error('[FCM] init error:', e); return admin.apps.length > 0 ? admin.app() : null }
}

export function getMessaging(): admin.messaging.Messaging | null {
  const app = getFirebaseAdmin(); if (!app) return null; return admin.messaging(app)
}
```

#### 3-3. Prisma 스키마 추가(토큰/발송 이력)
```prisma
// prisma/schema.prisma (발췌)
model FcmToken {
  id         String   @id @default(uuid())
  userId     String?
  token      String   @unique
  platform   String
  deviceId   String?
  isActive   Boolean  @default(true)
  lastUsedAt DateTime?
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt

  @@index([userId])
  @@index([token])
  @@index([deviceId])
}

model PushNotification {
  id           String   @id @default(uuid())
  userId       String?
  fcmTokenId   String?
  title        String
  body         String
  data         Json?
  type         String   @default("pending")
  status       String   @default("pending")
  messageId    String?
  error        String?
  attemptCount Int      @default(0)
  createdAt    DateTime @default(now())
  sentAt       DateTime?
  isRead       Boolean  @default(false)
  readAt       DateTime?

  @@index([userId])
  @@index([type])
  @@index([status])
  @@index([createdAt])
}
```

DB 반영(둘 중 택1)
- 개발/간편: `npx prisma db push`
- 정식: `npx prisma migrate dev --name add-fcm-tables` → 배포에서 `npx prisma migrate deploy`

#### 3-4. 토큰 등록/삭제 API
```ts
// app/api/fcm/token/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { createClient } from '@/lib/supabase/server'

export async function POST(req: NextRequest) {
  const { token, userId, platform, deviceId } = await req.json()
  if (!token) return NextResponse.json({ success: false, message: 'token required' }, { status: 400 })

  let resolvedUserId: string | null = userId ?? null
  try {
    const supabase = await createClient(); const { data: { user } } = await supabase.auth.getUser()
    if (user?.email) {
      const u = await prisma.user.findUnique({ where: { email: user.email } });
      if (u) resolvedUserId = u.id
    }
  } catch {}

  const saved = await prisma.fcmToken.upsert({
    where: { token },
    create: { token, platform: platform ?? 'unknown', deviceId, userId: resolvedUserId, isActive: true, lastUsedAt: new Date() },
    update: { platform: platform ?? undefined, deviceId, userId: resolvedUserId ?? undefined, isActive: true, lastUsedAt: new Date() }
  })
  return NextResponse.json({ success: true, token: saved })
}

export async function DELETE(req: NextRequest) {
  const { token } = await req.json(); if (!token) return NextResponse.json({ success: false }, { status: 400 })
  const existing = await prisma.fcmToken.findUnique({ where: { token } }); if (!existing) return NextResponse.json({ success: false }, { status: 404 })
  const updated = await prisma.fcmToken.update({ where: { token }, data: { isActive: false, lastUsedAt: new Date() }})
  return NextResponse.json({ success: true, token: updated })
}
```

#### 3-5. 발송 API(유니캐스트/브로드캐스트)
```ts
// app/api/admin/fcm/unicast/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { createClient } from '@/lib/supabase/server'
import { getMessaging } from '@/lib/firebase-admin'

export async function POST(request: NextRequest) {
  const supabase = await createClient(); const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ success: false }, { status: 401 })
  const me = await prisma.user.findUnique({ where: { email: user.email! }, select: { role: true } })
  if (me?.role !== 'ADMIN') return NextResponse.json({ success: false }, { status: 403 })

  const { userId, token, title, body: msgBody, data, foreground = false } = await request.json()
  if ((!userId && !token) || !title || !msgBody) return NextResponse.json({ success: false }, { status: 400 })

  const m = getMessaging(); if (!m) return NextResponse.json({ success: false }, { status: 500 })
  let target = token as string | null
  if (!target && userId) {
    const row = await prisma.fcmToken.findFirst({ where: { userId, isActive: true }, orderBy: [{ lastUsedAt: 'desc' }, { updatedAt: 'desc' }] })
    if (!row) return NextResponse.json({ success: false, message: 'no token' }, { status: 404 })
    target = row.token
  }

  const message: any = {
    token: target!,
    notification: { title, body: msgBody },
    data: { ...(data || {}), showForeground: foreground ? 'true' : 'false' },
    apns: { payload: { aps: { alert: { title, body: msgBody }, sound: 'default', badge: 1 } } },
  }
  try {
    const res = await m.send(message)
    await prisma.pushNotification.create({ data: { userId: userId ?? null, fcmTokenId: null, title, body: msgBody, data: data || {}, type: 'unicast', status: 'sent', messageId: res, sentAt: new Date() } })
    return NextResponse.json({ success: true })
  } catch (e: any) {
    await prisma.pushNotification.create({ data: { userId: userId ?? null, title, body: msgBody, data: data || {}, type: 'unicast', status: 'failed', error: e?.message || 'unknown', attemptCount: 1 } })
    return NextResponse.json({ success: false, error: e?.message }, { status: 500 })
  }
}
```

```ts
// app/api/admin/fcm/broadcast/route.ts (발췌)
const { title, body: msgBody, data, platform, onlyActive = true, foreground = false } = await request.json()
...
const messages = batch.map((t) => ({
  token: t.token,
  notification: { title, body: msgBody },
  data: { ...(data || {}), showForeground: foreground ? 'true' : 'false' },
  apns: { payload: { aps: { alert: { title, body: msgBody }, sound: 'default', badge: 1 } } }
}))
```

---

### 4) 관리자 페이지(테스트 콘솔)
유니캐스트/브로드캐스트 전송, “앱 활성화 시에도 표시(포그라운드 배너)” 스위치 포함.

핵심: 전송 payload에 `foreground: true`를 넣으면 `data.showForeground='true'`로 내려가고, iOS는 시스템 배너가 항상 표시됩니다(현재 설정).

```tsx
// app/admin/fcm/page.tsx (핵심 발췌)
const [foreground, setForeground] = useState(false)
...
const payload = { title, body, data: parseData(), onlyActive, foreground }
await axios.post('/api/admin/fcm/broadcast', payload)
```

---

### 5) 환경변수 예시(.env.local)
```env
# 서버용 (아래 중 하나만 채우면 됨)
FIREBASE_SERVICE_ACCOUNT_BASE64=eyJ0eXBlIjoic2VydmljZV9hY2NvdW50Ii4uLn0=
# 또는
FIREBASE_SERVICE_ACCOUNT_PATH=/absolute/path/to/firebase-service-account.json
# 또는
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n
DATABASE_URL=postgresql://...
```

BASE64 만들기(macOS):
```bash
base64 -i "/path/to/firebase-service-account.json" | tr -d '\n' > /tmp/firebase-service-account.b64
```

---

### 6) 테스트
1) iOS 디바이스에서 앱 실행 → 알림 권한 허용 → 토큰 발급 로그 확인
2) 웹이 `/api/fcm/token`에 저장(Prisma Studio로 `FcmToken` 확인)
3) 관리자 `/admin/fcm`에서 유니/브로드캐스트 전송
4) 포그라운드/백그라운드 모두 배너 표시 확인

수동 등록(curl) 예시:
```bash
curl -X POST https://your-domain.com/api/fcm/token \
  -H 'Content-Type: application/json' \
  -d '{"token":"DEVICE_FCM_TOKEN","platform":"ios","deviceId":"test-device"}'
```

---

### 7) 트러블슈팅
- iOS 빌드 시 “firebase_core requires higher minimum iOS” → Podfile platform 15.0 설정
- “No app has been configured yet.” → iOS에선 `Firebase.initializeApp()` (GoogleService-Info.plist 포함 필수)
- 포그라운드에서 배너 미표시 → `setForegroundNotificationPresentationOptions(alert:true,...)` 확인
- 서버 500(FCM Admin) → 서비스 계정 환경변수 확인(Base64 권장), `firebase-admin` 설치 여부 확인
- 서버 400(브로드캐스트) → 활성 토큰이 없음. 토큰 저장 흐름(브릿지 전역 마운트) 확인

---

### 8) 파일/포인트 요약(복붙 체크리스트)
- Flutter: `main.dart`, `services/fcm_service.dart`, `screens/webview_screen.dart`
- iOS: `ios/Podfile`(platform 15.0), Runner에 `GoogleService-Info.plist`
- Web: `hooks/useWebViewBridge.ts`, `components/webview-bridge-initializer.tsx`, `app/layout.tsx`에 마운트
- 서버: `lib/firebase-admin.ts`, `app/api/fcm/token/route.ts`, `app/api/admin/fcm/(unicast|broadcast)/route.ts`
- DB: `prisma/schema.prisma`의 `FcmToken`, `PushNotification` 추가 후 `prisma db push` 또는 `migrate`

이 가이드를 다른 프로젝트에 그대로 이식하면, iOS 앱(WebView)과 Web(Next.js) 조합에서 FCM 토큰 저장/발송/표시까지 바로 동작합니다.


