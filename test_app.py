import os
import sys
from openai import OpenAI

gateway_ip = os.getenv("AI_GATEWAY_IP")
if not gateway_ip:
    print("Error: AI_GATEWAY_IP 환경변수가 설정되지 않았습니다.")
    sys.exit(1)

# AI 게이트웨이 엔드포인트 호출 (포트 4000)
client = OpenAI(
    base_url=f"http://{gateway_ip}:4000/v1",
    api_key="sk-dummy-key"  # 실제 OpenAI 키는 게이트웨이가 관리
)

try:
    print(f"Connecting to AI Gateway at http://{gateway_ip}:4000/v1 ...")
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": "GitHub Actions에서 전송된 테스트 프롬프트입니다."}]
    )
    print("✅ 테스트 성공! AI 게이트웨이 응답 수신:")
    print(response.choices[0].message.content)
except Exception as e:
    print(f"❌ 연동 테스트 실패: {e}")
    sys.exit(1)