from __future__ import annotations

import asyncio
import contextlib
import random
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Literal

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
import os

app = FastAPI(title="atc-backend", version="0.1.0")

# 정적 파일 경로 설정 (app 디렉토리 내부의 static 폴더)
static_path = os.path.join(os.path.dirname(__file__), "static")
app.mount("/static", StaticFiles(directory=static_path), name="static")

@app.get("/")
async def read_index():
    return FileResponse(os.path.join(static_path, "index.html"))

# Dev-friendly CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@dataclass
class RoomState:
    code: str
    created_at: float = field(default_factory=lambda: time.time())
    sockets: set[WebSocket] = field(default_factory=set)
    # 참가자 데이터 저장 (client_id -> info)
    participants: dict[str, dict] = field(default_factory=dict)
    # 지목 데이터 (voter_id -> target_id)
    picks: dict[str, str] = field(default_factory=dict)

ROOMS: dict[str, RoomState] = {}

class CreateRoomResponse(BaseModel):
    room_code: str

@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

@app.post("/rooms", response_model=CreateRoomResponse)
def create_room() -> CreateRoomResponse:
    code = uuid.uuid4().hex[:6].upper()
    ROOMS[code] = RoomState(code=code)
    return CreateRoomResponse(room_code=code)

async def broadcast(room: RoomState, message: dict[str, Any]) -> None:
    dead: list[WebSocket] = []
    for ws in list(room.sockets):
        try:
            await ws.send_json(message)
        except Exception:
            dead.append(ws)
    for ws in dead:
        room.sockets.discard(ws)

@app.websocket("/ws/{room_code}")
async def ws_room(websocket: WebSocket, room_code: str) -> None:
    await websocket.accept()

    room_code = room_code.upper()
    if room_code not in ROOMS:
        ROOMS[room_code] = RoomState(code=room_code)

    room = ROOMS[room_code]
    client_id = uuid.uuid4().hex[:4]
    room.sockets.add(websocket)

    try:
        while True:
            data = await websocket.receive_json()
            event_type = data.get("type")

            if event_type == "join":
                gender = data.get("gender", "M")
                nickname = data.get("nickname", "익명").strip()
                team = "남성" if gender == "M" else "여성"
                name = nickname if nickname else f"{team} {len(room.participants) + 1}"
                
                room.participants[client_id] = {"id": client_id, "team": team, "name": name, "gender": gender}

                await websocket.send_json({
                    "type": "state",
                    "room_code": room.code,
                    "my_id": client_id,
                    "participants": list(room.participants.values())
                })
                await broadcast(room, {"type": "presence", "participants": list(room.participants.values())})

            elif event_type == "pick":
                target_id = data.get("target_id")
                room.picks[client_id] = target_id
                await websocket.send_json({"type": "pick_confirmed", "target_id": target_id})

                # 모든 참가자가 투표를 마쳤는지 확인
                if len(room.picks) >= len(room.participants) and len(room.participants) > 1:
                    males = [p for p in room.participants.values() if p['gender'] == 'M']
                    females = [p for p in room.participants.values() if p['gender'] == 'F']
                    
                    unpaired_m_ids = {p['id'] for p in males}
                    unpaired_f_ids = {p['id'] for p in females}
                    final_pairs = []

                    # 1순위: 서로 지목 (Mutual)
                    for f_id in list(unpaired_f_ids):
                        target_m_id = room.picks.get(f_id)
                        if target_m_id in unpaired_m_ids and room.picks.get(target_m_id) == f_id:
                            final_pairs.append((f_id, target_m_id))
                            unpaired_f_ids.remove(f_id)
                            unpaired_m_ids.remove(target_m_id)

                    # 2순위: 여자 기준 지목 (Female's choice)
                    targeted_by = {}
                    for f_id in unpaired_f_ids:
                        target_m_id = room.picks.get(f_id)
                        if target_m_id in unpaired_m_ids:
                            if target_m_id not in targeted_by:
                                targeted_by[target_m_id] = []
                            targeted_by[target_m_id].append(f_id)
                    
                    m_ids_to_process = list(targeted_by.keys())
                    random.shuffle(m_ids_to_process)
                    for m_id in m_ids_to_process:
                        if m_id in unpaired_m_ids:
                            f_list = targeted_by[m_id]
                            chosen_f = random.choice(f_list)
                            final_pairs.append((chosen_f, m_id))
                            unpaired_f_ids.remove(chosen_f)
                            unpaired_m_ids.remove(m_id)

                    # 3순위: 나머지 랜덤
                    remaining_f = list(unpaired_f_ids)
                    remaining_m = list(unpaired_m_ids)
                    random.shuffle(remaining_f)
                    random.shuffle(remaining_m)
                    while remaining_f and remaining_m:
                        final_pairs.append((remaining_f.pop(), remaining_m.pop()))
                    
                    # 결과 메시지 구성
                    result_message = "🎉 운명의 자리 배치표 발표! 🎉\n\n"
                    random.shuffle(final_pairs)
                    for f_id, m_id in final_pairs:
                        f_name = room.participants[f_id]['name']
                        m_name = room.participants[m_id]['name']
                        result_message += f"✨ {f_name}  X  {m_name}\n"
                    
                    if remaining_f or remaining_m:
                        result_message += "\n⚠️ 인원이 맞지 않아 일부 인원은 자리가 고정되었습니다."
                    
                    result_message += "\n\n모두 위 명단대로 자리를 이동해 주세요!"

                    await broadcast(room, {"type": "final_result", "message": result_message})
                    room.picks.clear()
                    await broadcast(room, {"type": "pick_reset"})

    except WebSocketDisconnect:
        pass
    finally:
        room.sockets.discard(websocket)
        room.participants.pop(client_id, None)
        room.picks.pop(client_id, None)
        await broadcast(room, {"type": "presence", "participants": list(room.participants.values())})
