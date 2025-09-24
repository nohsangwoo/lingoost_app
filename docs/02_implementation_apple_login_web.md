# Apple 웹 로그인 구현 가이드

## 개요
Supabase를 통한 Apple OAuth 로그인을 Next.js 웹 애플리케이션에 구현하는 방법입니다.

## 사전 준비 사항

### 1. Apple Developer 설정
- Apple Developer 계정 필요
- App ID 생성 및 Sign in with Apple 활성화
- Service ID 생성 (웹용)
- Key 생성 (Sign in with Apple용)

### 2. Supabase 설정
- Supabase Dashboard에서 Apple Provider 활성화
- Client ID (Service ID) 입력
- Secret Key 입력

## 구현 단계

### 1. Auth Store 수정 (`/store/auth-store.ts`)

#### Apple Provider 타입 추가
```typescript
// OAuth 로그인 함수 시그니처 수정
signInWithOAuth: (provider: 'google' | 'github' | 'facebook' | 'apple') => Promise<SignInResult>

// OAuth 로그인 함수 구현부 수정
signInWithOAuth: async (provider: 'google' | 'github' | 'facebook' | 'apple'): Promise<SignInResult> => {
  try {
    set({ isLoading: true, error: null })
    
    const redirectUrl = typeof window !== 'undefined' 
      ? `${window.location.origin}/auth/callback`
      : `${process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'}/auth/callback`
    
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: redirectUrl,
      },
    })

    if (error) {
      set({ error: error.message, isLoading: false })
      return { success: false, error: error.message }
    }

    if (!data?.url) {
      const errorMsg = 'OAuth URL을 가져올 수 없습니다'
      set({ error: errorMsg, isLoading: false })
      return { success: false, error: errorMsg }
    }

    set({ isLoading: false })
    return { success: true, url: data.url }

  } catch (error: any) {
    const errorMsg = error.message || 'OAuth 로그인 중 오류가 발생했습니다'
    set({ error: errorMsg, isLoading: false })
    return { success: false, error: errorMsg }
  }
}
```

### 2. 로그인 페이지 수정 (`/app/login/page.tsx`)

#### 필요한 import 추가
```typescript
import { FcGoogle } from 'react-icons/fc'
import { SiApple } from 'react-icons/si'  // Apple 아이콘 추가
```

#### Apple 로그인 핸들러 추가
```typescript
const handleAppleLogin = async () => {
  setIsLoading(true)

  try {
    // WebView에서 iOS 기기인 경우 네이티브 Apple 로그인 처리
    if (deviceInfo.isWebView && (deviceInfo.isIOS || deviceInfo.isIPad)) {
      if ((window as any).flutter_inappwebview) {
        (window as any).flutter_inappwebview.callHandler('appleSignIn')
        
        (window as any).handleAppleSignInResponse = async (data: { 
          idToken: string; 
          authorizationCode?: string 
        }) => {
          const response = await fetch('/api/mobile/handoff', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              idToken: data.idToken,
              authorizationCode: data.authorizationCode
            })
          })

          if (response.ok) {
            const { code } = await response.json()
            window.location.href = `/auth/consume?code=${code}`
          } else {
            toast.error('Apple 로그인 실패')
          }
        }
      }
    } else {
      // 일반 웹 브라우저에서 OAuth 플로우 처리
      const result = await authStore.signInWithOAuth('apple')
      
      if (result?.error) {
        toast.error('Apple 로그인 실패', {
          description: result.error
        })
      } else if (result?.url) {
        window.location.href = result.url
      }
    }
  } catch (error) {
    console.error('Apple login error:', error)
    toast.error('Apple 로그인 중 오류가 발생했습니다')
  } finally {
    setIsLoading(false)
  }
}
```

#### UI에 Apple 로그인 버튼 추가

##### 데스크톱 버전
```tsx
{/* Social Login Buttons */}
<div className="space-y-3">
  {/* Google Login Button */}
  <Button
    type="button"
    variant="outline"
    fullWidth
    size="lg"
    onClick={handleGoogleLogin}
    isLoading={isLoading}
    className="h-12 text-base font-semibold border-gray-300 hover:bg-gray-50"
  >
    <FcGoogle className="h-5 w-5 mr-3" />
    Google로 계속하기
  </Button>

  {/* Apple Login Button */}
  <Button
    type="button"
    variant="outline"
    fullWidth
    size="lg"
    onClick={handleAppleLogin}
    isLoading={isLoading}
    className="h-12 text-base font-semibold border-gray-900 bg-black text-white hover:bg-gray-900"
  >
    <SiApple className="h-5 w-5 mr-3" />
    Apple로 계속하기
  </Button>
</div>
```

##### 모바일 버전
```tsx
{/* Social Login Buttons for Mobile */}
<div className="space-y-3">
  {/* Google Login Button */}
  <Button
    type="button"
    variant="outline"
    fullWidth
    size="lg"
    onClick={handleGoogleLogin}
    isLoading={isLoading}
    className="border-gray-300 hover:bg-gray-50"
  >
    <FcGoogle className="h-5 w-5 mr-2" />
    Google로 계속하기
  </Button>

  {/* Apple Login Button */}
  <Button
    type="button"
    variant="outline"
    fullWidth
    size="lg"
    onClick={handleAppleLogin}
    isLoading={isLoading}
    className="border-gray-900 bg-black text-white hover:bg-gray-900"
  >
    <SiApple className="h-5 w-5 mr-2" />
    Apple로 계속하기
  </Button>
</div>
```

## 주요 특징

### 1. 플랫폼별 처리
- **웹 브라우저**: Supabase OAuth 플로우를 통한 Apple 로그인
- **iOS WebView**: 네이티브 Apple Sign-In SDK를 통한 로그인

### 2. 보안
- OAuth 2.0 표준 준수
- PKCE (Proof Key for Code Exchange) 지원
- 리다이렉트 URL 검증

### 3. 사용자 경험
- Apple의 디자인 가이드라인 준수 (검은색 버튼)
- 로딩 상태 표시
- 에러 처리 및 사용자 피드백

## 필요한 패키지

```json
{
  "dependencies": {
    "react-icons": "^5.5.0",  // Apple 아이콘 제공
    "@supabase/ssr": "latest",
    "@supabase/supabase-js": "latest",
    "zustand": "latest"
  }
}
```

## 환경 변수 설정

`.env.local` 파일:
```env
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
NEXT_PUBLIC_APP_URL=https://your-domain.com  # 프로덕션 환경
```

## 테스트 체크리스트

- [ ] 웹 브라우저에서 Apple 로그인 버튼 클릭
- [ ] Supabase OAuth 리다이렉트 확인
- [ ] Apple ID 로그인 페이지 표시 확인
- [ ] 로그인 후 콜백 URL로 리다이렉트 확인
- [ ] 세션 생성 및 사용자 정보 저장 확인
- [ ] 로그아웃 후 재로그인 테스트

## 트러블슈팅

### 1. "Invalid client" 에러
- Supabase Dashboard에서 Client ID 확인
- Apple Developer Console에서 Service ID 확인

### 2. 리다이렉트 실패
- Apple Developer Console에서 Return URL 설정 확인
- Supabase의 Redirect URL과 일치하는지 확인

### 3. 세션 생성 실패
- Supabase Auth 설정 확인
- 네트워크 요청 로그 확인

## 참고 자료

- [Supabase Apple Auth Documentation](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Apple Sign in with Apple JS](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_js)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)