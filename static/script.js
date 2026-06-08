let socket = null;
let myId = null;
let selectedTargetId = null;

const joinSection = document.getElementById('join-section');
const gameSection = document.getElementById('game-section');
const participantList = document.getElementById('participant-list');
const waitMsg = document.getElementById('wait-msg');
const resultModal = document.getElementById('result-modal');
const resultText = document.getElementById('result-text');

// 룸 입장
document.getElementById('join-btn').onclick = () => {
    const roomCode = document.getElementById('room-code').value.toUpperCase();
    const nickname = document.getElementById('nickname').value;
    const gender = document.querySelector('input[name="gender"]:checked').value;

    if (!roomCode || !nickname) return alert('룸 코드와 닉네임을 입력하세요.');

    // 현재 호스트의 WebSocket 주소 생성
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws/${roomCode}`;
    
    socket = new WebSocket(wsUrl);

    socket.onopen = () => {
        socket.send(JSON.stringify({ type: 'join', gender, nickname }));
    };

    socket.onmessage = (event) => {
        const data = JSON.parse(event.data);
        handleServerEvent(data);
    };

    socket.onclose = () => {
        alert('연결이 종료되었습니다.');
        location.reload();
    };
};

function handleServerEvent(data) {
    if (data.type === 'state') {
        myId = data.my_id;
        document.getElementById('display-room-code').innerText = data.room_code;
        joinSection.classList.add('hidden');
        gameSection.classList.remove('hidden');
        updateParticipants(data.participants);
    } 
    else if (data.type === 'presence') {
        updateParticipants(data.participants);
    }
    else if (data.type === 'pick_confirmed') {
        selectedTargetId = data.target_id;
        renderParticipantsUI();
    }
    else if (data.type === 'final_result') {
        resultText.innerText = data.message;
        resultModal.classList.remove('hidden');
    }
    else if (data.type === 'pick_reset') {
        selectedTargetId = null;
        renderParticipantsUI();
    }
}

let currentParticipants = [];
function updateParticipants(participants) {
    currentParticipants = participants;
    const myInfo = participants.find(p => p.id === myId);
    if (myInfo) {
        document.getElementById('display-nickname').innerText = myInfo.name;
        document.getElementById('display-team').innerText = myInfo.team;
    }
    renderParticipantsUI();
}

function renderParticipantsUI() {
    participantList.innerHTML = '';
    const myInfo = currentParticipants.find(p => p.id === myId);
    const myTeam = myInfo ? myInfo.team : null;

    // 이성 팀원만 노출
    const potentialMatches = currentParticipants.filter(p => p.team !== myTeam);

    if (potentialMatches.length === 0) {
        waitMsg.classList.remove('hidden');
    } else {
        waitMsg.classList.add('hidden');
        potentialMatches.forEach(p => {
            const chip = document.createElement('div');
            chip.className = `chip ${selectedTargetId === p.id ? 'selected' : ''}`;
            chip.innerText = p.name;
            chip.onclick = () => {
                socket.send(JSON.stringify({ type: 'pick', target_id: p.id }));
            };
            participantList.appendChild(chip);
        });
    }
}

// 모달 닫기
document.getElementById('close-modal-btn').onclick = () => {
    resultModal.classList.add('hidden');
};

// 연결 해제
document.getElementById('disconnect-btn').onclick = () => {
    if (socket) socket.close();
};
