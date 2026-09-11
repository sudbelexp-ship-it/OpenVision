#!/usr/bin/env python3
"""
Smoke-тест GigaChat API (developers.sber.ru) — только стандартная библиотека + requests.

Проверяет всю цепочку, которую позже нужно повторить в Swift-коде (Фаза 3b):
  1. OAuth: Authorization Key -> Access Token.
  2. GET /api/v1/models — список доступных моделей.
  3. POST /api/v1/files — загрузка tools/test.jpg.
  4. POST /api/v1/chat/completions с attachments (модель GigaChat-2-Max).
  5. DELETE файла после использования.

Запуск (PowerShell), см. tools/README.md:
    pip install requests
    $env:GIGACHAT_AUTH_KEY = "<ключ из личного кабинета developers.sber.ru>"
    python tools\\gigachat_smoke.py

Ключ и токен НИКОГДА не печатаются в вывод целиком — только длина/наличие.
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path

import requests

OAUTH_URL = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth"
API_BASE = "https://gigachat.devices.sberbank.ru/api/v1"
SCOPE = "GIGACHAT_API_PERS"
VISION_MODEL = "GigaChat-2-Max"

REPO_ROOT = Path(__file__).resolve().parent.parent
CA_CERT_PATH = REPO_ROOT / "certs" / "russian_trusted_root_ca.pem"
TEST_IMAGE_PATH = REPO_ROOT / "tools" / "test.jpg"


def fail(message: str) -> None:
    print(f"ОШИБКА: {message}", file=sys.stderr)
    sys.exit(1)


def get_access_token(auth_key: str) -> dict:
    """OAuth: Authorization Key -> Access Token. Возвращает { access_token, expires_at }."""
    headers = {
        "Authorization": f"Basic {auth_key}",
        "RqUID": str(uuid.uuid4()),
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    }
    resp = requests.post(
        OAUTH_URL,
        headers=headers,
        data={"scope": SCOPE},
        verify=str(CA_CERT_PATH),
        timeout=30,
    )
    if resp.status_code != 200:
        fail(f"OAuth не удался: HTTP {resp.status_code} — {resp.text[:300]}")
    data = resp.json()
    if "access_token" not in data:
        fail(f"В ответе OAuth нет access_token. Поля ответа: {sorted(data.keys())}")
    return data


def list_models(token: str) -> dict:
    resp = requests.get(
        f"{API_BASE}/models",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=str(CA_CERT_PATH),
        timeout=30,
    )
    if resp.status_code != 200:
        fail(f"GET /models не удался: HTTP {resp.status_code} — {resp.text[:300]}")
    return resp.json()


def upload_file(token: str, image_path: Path) -> dict:
    with image_path.open("rb") as f:
        files = {"file": (image_path.name, f, "image/jpeg")}
        resp = requests.post(
            f"{API_BASE}/files",
            headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
            files=files,
            data={"purpose": "general"},
            verify=str(CA_CERT_PATH),
            timeout=60,
        )
    if resp.status_code != 200:
        fail(f"POST /files не удался: HTTP {resp.status_code} — {resp.text[:300]}")
    return resp.json()


def chat_with_image(token: str, file_id: str) -> dict:
    payload = {
        "model": VISION_MODEL,
        "messages": [
            {
                "role": "system",
                "content": (
                    "Ты голосовой ассистент в умных очках. Отвечай по-русски, коротко: "
                    "1-3 предложения, без списков и разметки, так как ответ будет озвучен."
                ),
            },
            {
                "role": "user",
                "content": "Что изображено на этой картинке?",
                "attachments": [file_id],
            },
        ],
    }
    resp = requests.post(
        f"{API_BASE}/chat/completions",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        json=payload,
        verify=str(CA_CERT_PATH),
        timeout=60,
    )
    if resp.status_code != 200:
        fail(f"POST /chat/completions не удался: HTTP {resp.status_code} — {resp.text[:300]}")
    return resp.json()


def delete_file(token: str, file_id: str) -> None:
    # Официальный REST-эндпоинт удаления — POST /files/{file_id}/delete (не DELETE-метод).
    resp = requests.post(
        f"{API_BASE}/files/{file_id}/delete",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        verify=str(CA_CERT_PATH),
        timeout=30,
    )
    if resp.status_code != 200:
        print(
            f"ПРЕДУПРЕЖДЕНИЕ: не удалось удалить файл {file_id}: "
            f"HTTP {resp.status_code} — {resp.text[:300]}",
            file=sys.stderr,
        )
    else:
        print(f"Файл {file_id} удалён из хранилища GigaChat.")


def main() -> None:
    auth_key = os.environ.get("GIGACHAT_AUTH_KEY", "").strip()
    if not auth_key:
        fail("Переменная окружения GIGACHAT_AUTH_KEY не задана. См. tools/README.md.")

    if not CA_CERT_PATH.is_file():
        fail(f"Не найден сертификат {CA_CERT_PATH}")
    if not TEST_IMAGE_PATH.is_file():
        fail(f"Не найден тестовый файл {TEST_IMAGE_PATH}")

    print("1/5 Получение access token (OAuth)...")
    token_data = get_access_token(auth_key)
    access_token = token_data["access_token"]
    expires_at = token_data.get("expires_at")
    print(f"    OK. Токен получен (длина {len(access_token)} символов).")
    if expires_at is not None:
        print(f"    expires_at = {expires_at} (сырое значение из ответа, см. ниже про формат)")

    print("2/5 GET /api/v1/models...")
    models = list_models(access_token)
    model_ids = [m.get("id") for m in models.get("data", [])]
    print(f"    OK. Доступно моделей: {len(model_ids)}. Примеры: {model_ids[:5]}")

    print(f"3/5 Загрузка {TEST_IMAGE_PATH.name} через POST /api/v1/files...")
    file_info = upload_file(access_token, TEST_IMAGE_PATH)
    file_id = file_info.get("id")
    if not file_id:
        fail(f"В ответе /files нет поля id. Ответ: {json.dumps(file_info, ensure_ascii=False)}")
    print(f"    OK. file_id = {file_id}")

    print(f"4/5 POST /api/v1/chat/completions (модель {VISION_MODEL})...")
    chat_response = chat_with_image(access_token, file_id)
    try:
        answer = chat_response["choices"][0]["message"]["content"]
    except (KeyError, IndexError) as e:
        fail(
            "Не удалось извлечь ответ из choices[0].message.content: "
            f"{e}. Полный ответ: {json.dumps(chat_response, ensure_ascii=False)}"
        )
    print("    OK. Ответ модели:")
    print(f"    >>> {answer}")

    print("5/5 Удаление загруженного файла...")
    delete_file(access_token, file_id)

    print("\nГотово. Смоук-тест GigaChat пройден успешно.")
    print(
        "\nДля Фазы 3b (Swift): скопируйте JSON-структуру ответов (без токена/ключа) "
        "в NOTES.md — понадобятся точные поля OAuth (expires_at), /files (id) и "
        "/chat/completions (choices)."
    )


if __name__ == "__main__":
    main()
