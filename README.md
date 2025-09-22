
### 설치 및 실행

1. **의존성 설치**
```bash
flutter pub get
```

2. **iOS 시뮬레이터 실행**
```bash
flutter run
```

3. **Android 에뮬레이터 실행**
```bash
flutter run -d android
```

## 🔧 환경 설정

### Supabase 설정
`lib/constants/app_config.dart`에서 Supabase 설정을 확인하세요:

```dart
class AppConfig {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
}
```



### 일반적인 문제

1. **패키지 설치 오류**
```bash
flutter clean
flutter pub get
```

2. **iOS 빌드 오류**
```bash
cd ios
pod install
cd ..
flutter run
```

3. **Android 빌드 오류**
- Android Studio에서 SDK 버전 확인
- `android/app/build.gradle`에서 minSdkVersion 확인

## 📞 지원

문제가 발생하거나 질문이 있으시면:
- 이슈 생성하여 문의
- 개발팀에 직접 연락

## 📄 라이선스

이 프로젝트는 개인/상업적 사용을 위한 것입니다.



# 버전업은 pubspec.yaml 파일의 version 값을 변경하고, 버전 번호를 증가시키세요.

# 버전 번호는 다음과 같은 형식으로 작성해야 합니다:

# 1.0.0+1

# 1.0.1+2

# 1.1.0+3

# 1.1.1+4

# 버전 + 빌드 번호

버전 변경 후 

flutter clean
flutter pub get
flutter build ios



# android

1. 수정
2. pubspec.yaml 파일의 version 값을 변경하고, 버전 번호를 증가시키세요.
3. flutter clean
4. flutter build appbundle
5. flutter build appbundle --release --obfuscate --split-debug-info=build/symbols 
(경고 해결)

6. 번들된 파일을 새버전으로 게시하여 검사


7. 에뮬레이터 실행 후 
# 그냥 플러터 실행
flutter run  
flutter run -d (디버깅? 디버그 모드?)
flutter run -d 00008130-0004543201F0001C (마지막은 아이디 필요함)

# 무수히 많은 flutter E/FrameEvents( 5424): updateAcquireFence: Did not find frame. 로그 안보이게
flutter run | grep -v "updateAcquireFence"
