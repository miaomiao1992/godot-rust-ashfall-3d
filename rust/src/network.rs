//! LAN discovery and ENet transport. Engine reflection is confined to this adapter;
//! wire data and connection ownership remain ordinary, testable Rust values.
use godot::classes::{ClassDb, INode, Node, Object};
use godot::prelude::*;
use serde::{Deserialize, Serialize};
use std::cell::RefCell;
use std::collections::{BTreeMap, VecDeque};
use std::io::ErrorKind;
use std::net::{SocketAddr, UdpSocket};
use std::rc::Rc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const PROTOCOL: u16 = 1;
const BUILD: &str = "0.5.0-lan";
const LIMIT: usize = 1_048_576;
// First-use shader compilation and scene loading can stall the engine thread.
// Leave enough time for those stalls; explicit ENet disconnects remain immediate.
const MEMBER_TIMEOUT: Duration = Duration::from_secs(30);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(45);

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Member {
    pub id: u32,
    pub name: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Room {
    pub magic: String,
    pub protocol: u16,
    pub build: String,
    pub room_id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub players: usize,
    pub capacity: usize,
    #[serde(default)]
    pub mode: String,
    pub playing: bool,
    pub stage: i32,
    pub wave: i32,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InputFrame {
    pub x: f32,
    pub z: f32,
    pub yaw: f32,
    pub pitch: f32,
    pub buttons: u32,
    pub seq: u64,
}
impl InputFrame {
    fn valid(&self) -> bool {
        [self.x, self.z, self.yaw, self.pitch]
            .iter()
            .all(|x| x.is_finite())
            && self.x.abs() <= 1.01
            && self.z.abs() <= 1.01
            && self.pitch.abs() <= 1.6
            && self.buttons <= 31
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionKind {
    Fire,
    Reload,
    Switch,
    Interact,
    Upgrade,
    Ready,
    Restart,
    Team,
    Grenade,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Action {
    pub kind: ActionKind,
    pub arg: i32,
    pub seq: u64,
    pub yaw: f32,
    pub pitch: f32,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "data", rename_all = "snake_case")]
enum Wire {
    Hello {
        build: String,
        name: String,
    },
    Welcome {
        room: Room,
        members: Vec<Member>,
    },
    Input(InputFrame),
    Action(Action),
    Snapshot(serde_json::Value),
    Event {
        kind: String,
        data: serde_json::Value,
    },
    Heartbeat,
    Leave,
    Reject(String),
}
#[derive(Serialize, Deserialize)]
struct Envelope {
    protocol: u16,
    message: Wire,
}

fn encode(message: Wire, compressed: bool) -> Result<Vec<u8>, String> {
    let json = serde_json::to_vec(&Envelope {
        protocol: PROTOCOL,
        message,
    })
    .map_err(|e| e.to_string())?;
    if json.len() > LIMIT {
        return Err("packet too large".into());
    }
    let mut bytes = b"AFN1".to_vec();
    bytes.push(u8::from(compressed));
    if compressed {
        bytes.extend(miniz_oxide::deflate::compress_to_vec(&json, 3));
    } else {
        bytes.extend(json);
    }
    Ok(bytes)
}
fn decode(bytes: &[u8]) -> Result<Wire, String> {
    if bytes.len() < 6 || bytes.len() > LIMIT || &bytes[..4] != b"AFN1" {
        return Err("invalid packet".into());
    }
    let payload = match bytes[4] {
        0 => bytes[5..].to_vec(),
        1 => miniz_oxide::inflate::decompress_to_vec_with_limit(&bytes[5..], LIMIT)
            .map_err(|_| "invalid compression")?,
        _ => return Err("invalid encoding".into()),
    };
    let envelope: Envelope = serde_json::from_slice(&payload).map_err(|e| e.to_string())?;
    if envelope.protocol != PROTOCOL {
        return Err("protocol mismatch".into());
    }
    Ok(envelope.message)
}
fn clean(text: &str, limit: usize) -> String {
    text.chars()
        .filter(|c| !c.is_control())
        .take(limit)
        .collect()
}

fn fragment(bytes: &[u8], transfer: u64) -> Vec<Vec<u8>> {
    if bytes.len() <= 1150 {
        return vec![bytes.to_vec()];
    }
    let count = bytes.len().div_ceil(1150);
    if count > 256 {
        return Vec::new();
    }
    bytes
        .chunks(1150)
        .enumerate()
        .map(|(index, chunk)| {
            let mut packet = b"AFF1".to_vec();
            packet.extend(transfer.to_le_bytes());
            packet.extend((index as u16).to_le_bytes());
            packet.extend((count as u16).to_le_bytes());
            packet.extend(chunk);
            packet
        })
        .collect()
}
struct Parts {
    chunks: Vec<Option<Vec<u8>>>,
    created: Instant,
}
#[derive(Default)]
struct Assemblies {
    pending: BTreeMap<(u32, u64), Parts>,
}
impl Assemblies {
    fn push(&mut self, sender: u32, packet: &[u8]) -> Option<Vec<u8>> {
        self.pending
            .retain(|_, p| p.created.elapsed() < Duration::from_secs(1));
        if packet.starts_with(b"AFN1") {
            return Some(packet.to_vec());
        }
        if packet.len() < 17 || packet.len() > 1166 || !packet.starts_with(b"AFF1") {
            return None;
        }
        let transfer = u64::from_le_bytes(packet[4..12].try_into().ok()?);
        let index = u16::from_le_bytes(packet[12..14].try_into().ok()?) as usize;
        let count = u16::from_le_bytes(packet[14..16].try_into().ok()?) as usize;
        if count == 0 || count > 256 || index >= count {
            return None;
        }
        let key = (sender, transfer);
        if !self.pending.contains_key(&key) && self.pending.len() >= 16 {
            self.pending.pop_first();
        }
        let parts = self.pending.entry(key).or_insert_with(|| Parts {
            chunks: vec![None; count],
            created: Instant::now(),
        });
        if parts.chunks.len() != count {
            return None;
        }
        parts.chunks[index] = Some(packet[16..].to_vec());
        if parts.chunks.iter().all(Option::is_some) {
            let parts = self.pending.remove(&key)?;
            return Some(parts.chunks.into_iter().flatten().flatten().collect());
        }
        None
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Role {
    Offline,
    Host,
    Client,
}
struct SeenRoom {
    room: Room,
    ip: String,
    seen: Instant,
}
struct Event {
    kind: String,
    peer: u32,
    data: String,
}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct LanSession {
    base: Base<Node>,
    role: Role,
    peer: Option<Gd<Object>>,
    local_id: u32,
    members: BTreeMap<u32, Member>,
    last_seen: BTreeMap<u32, Instant>,
    events: VecDeque<Event>,
    room: Option<Room>,
    rooms: BTreeMap<String, SeenRoom>,
    browser: Option<UdpSocket>,
    beacon: Option<UdpSocket>,
    discovery_port: u16,
    reliable: i64,
    unreliable: i64,
    connected: i64,
    disconnected: i64,
    timer: f64,
    heartbeat: f64,
    connecting_since: Instant,
    hello_sent: bool,
    nickname: String,
    disconnections: Rc<RefCell<Vec<u32>>>,
    reassembly: Assemblies,
    transfer: u64,
}

#[godot_api]
impl INode for LanSession {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            role: Role::Offline,
            peer: None,
            local_id: 0,
            members: BTreeMap::new(),
            last_seen: BTreeMap::new(),
            events: VecDeque::new(),
            room: None,
            rooms: BTreeMap::new(),
            browser: None,
            beacon: None,
            discovery_port: 42043,
            reliable: 2,
            unreliable: 0,
            connected: 2,
            disconnected: 0,
            timer: 0.0,
            heartbeat: 0.0,
            connecting_since: Instant::now(),
            hello_sent: false,
            nickname: String::new(),
            disconnections: Rc::new(RefCell::new(Vec::new())),
            reassembly: Assemblies::default(),
            transfer: 0,
        }
    }
    fn ready(&mut self) {
        self.base_mut()
            .set_process_mode(godot::classes::node::ProcessMode::ALWAYS);
        let db = ClassDb::singleton();
        self.reliable = db.class_get_integer_constant("MultiplayerPeer", "TRANSFER_MODE_RELIABLE");
        self.unreliable =
            db.class_get_integer_constant("MultiplayerPeer", "TRANSFER_MODE_UNRELIABLE");
        self.connected = db.class_get_integer_constant("MultiplayerPeer", "CONNECTION_CONNECTED");
        self.disconnected =
            db.class_get_integer_constant("MultiplayerPeer", "CONNECTION_DISCONNECTED");
    }
    fn process(&mut self, dt: f64) {
        self.poll_discovery(dt);
        let packets = self.poll_peer();
        let left = std::mem::take(&mut *self.disconnections.borrow_mut());
        if self.role == Role::Host && !left.is_empty() {
            for id in left {
                if self.members.remove(&id).is_some() {
                    self.last_seen.remove(&id);
                    self.event("peer_left", id, "{}");
                }
            }
            if let Some(room) = self.room.as_mut() {
                room.players = self.members.len();
            }
            self.roster();
        } else if self.role == Role::Client && left.contains(&1) {
            self.close_peer();
            self.event("disconnected", 0, "房主连接已断开");
        }
        for (sender, packet) in packets {
            if let Some(packet) = self.reassembly.push(sender, &packet)
                && let Ok(message) = decode(&packet)
            {
                self.receive(sender, message);
            }
        }
        if self.role == Role::Client {
            let status = self
                .peer
                .as_mut()
                .and_then(|p| p.try_call("get_connection_status", &[]).ok())
                .and_then(|v| v.try_to::<i64>().ok());
            if status == Some(self.connected) && !self.hello_sent {
                self.configure_peer_timeout(1);
                self.local_id = self
                    .peer
                    .as_mut()
                    .and_then(|p| p.try_call("get_unique_id", &[]).ok())
                    .and_then(|v| v.try_to::<u32>().ok())
                    .unwrap_or(0);
                self.hello_sent = true;
                self.send(
                    1,
                    Wire::Hello {
                        build: BUILD.into(),
                        name: self.nickname.clone(),
                    },
                    true,
                );
            }
            if (self.hello_sent && status == Some(self.disconnected))
                || (self.room.is_none() && self.connecting_since.elapsed() > CONNECT_TIMEOUT)
            {
                self.close_peer();
                self.event("disconnected", 0, "连接已断开或超时");
            }
            self.heartbeat += dt;
            if self.heartbeat >= 1.0 && self.hello_sent {
                self.heartbeat = 0.0;
                self.send(1, Wire::Heartbeat, true);
            }
        } else if self.role == Role::Host {
            let expired: Vec<u32> = self
                .last_seen
                .iter()
                .filter(|(_, t)| t.elapsed() > MEMBER_TIMEOUT)
                .map(|(id, _)| *id)
                .collect();
            for id in expired {
                self.remove_member(id);
            }
        }
    }
    fn exit_tree(&mut self) {
        self.close_peer();
    }
}

impl LanSession {
    fn configure_peer_timeout(&mut self, id: u32) {
        if let Some(peer) = self.peer.as_mut()
            && let Ok(value) = peer.try_call("get_peer", &[id.to_variant()])
            && let Ok(mut remote) = value.try_to::<Gd<Object>>()
        {
            let _ = remote.try_call(
                "set_timeout",
                &[
                    32i64.to_variant(),
                    30_000i64.to_variant(),
                    60_000i64.to_variant(),
                ],
            );
        }
    }
    fn event(&mut self, kind: &str, peer: u32, data: &str) {
        if self.events.len() < 2048 {
            self.events.push_back(Event {
                kind: kind.into(),
                peer,
                data: data.into(),
            });
        }
    }
    fn make_peer(&mut self) -> Result<Gd<Object>, String> {
        let mut peer = ClassDb::singleton()
            .instantiate("ENetMultiplayerPeer")
            .try_to::<Gd<Object>>()
            .map_err(|_| String::from("ENet 创建失败"))?;
        let queue = Rc::clone(&self.disconnections);
        let callback = Callable::from_fn("LanPeerDisconnected", move |args| {
            if let Some(value) = args.first()
                && let Ok(id) = value.try_to::<u32>()
            {
                queue.borrow_mut().push(id);
            }
        });
        let _ = peer.connect("peer_disconnected", &callback);
        Ok(peer)
    }
    fn send(&mut self, target: u32, message: Wire, reliable: bool) {
        let compressed = matches!(message, Wire::Snapshot(_));
        let Ok(bytes) = encode(message, compressed) else {
            return;
        };
        if self.disconnections.borrow().contains(&target) {
            return;
        }
        self.transfer = self.transfer.wrapping_add(1);
        let packets = fragment(&bytes, self.transfer);
        let Some(peer) = self.peer.as_mut() else {
            return;
        };
        let mode = if reliable {
            self.reliable
        } else {
            self.unreliable
        };
        let _ = peer.try_call("set_target_peer", &[target.to_variant()]);
        let _ = peer.try_call("set_transfer_mode", &[mode.to_variant()]);
        for packet in packets {
            let _ = peer.try_call(
                "put_packet",
                &[PackedByteArray::from(packet.as_slice()).to_variant()],
            );
        }
    }
    fn broadcast(&mut self, message: Wire, reliable: bool) {
        let peers: Vec<u32> = self.members.keys().copied().filter(|id| *id != 1).collect();
        for id in peers {
            self.send(id, message.clone(), reliable);
        }
    }
    fn poll_peer(&mut self) -> Vec<(u32, Vec<u8>)> {
        let mut result = Vec::new();
        let Some(peer) = self.peer.as_mut() else {
            return result;
        };
        let _ = peer.try_call("poll", &[]);
        for _ in 0..256 {
            let count = peer
                .try_call("get_available_packet_count", &[])
                .ok()
                .and_then(|v| v.try_to::<i64>().ok())
                .unwrap_or(0);
            if count == 0 {
                break;
            }
            let sender = peer
                .try_call("get_packet_peer", &[])
                .ok()
                .and_then(|v| v.try_to::<u32>().ok())
                .unwrap_or(0);
            if let Ok(v) = peer.try_call("get_packet", &[])
                && let Ok(bytes) = v.try_to::<PackedByteArray>()
            {
                result.push((sender, bytes.to_vec()));
            }
        }
        result
    }
    fn receive(&mut self, sender: u32, message: Wire) {
        if self.role == Role::Host {
            if sender <= 1 {
                return;
            }
            if self.members.contains_key(&sender) {
                self.last_seen.insert(sender, Instant::now());
            }
            match message {
                Wire::Hello { build, name } => {
                    self.configure_peer_timeout(sender);
                    if build != BUILD {
                        self.send(
                            sender,
                            Wire::Reject("版本不匹配，请使用 LAN v0.5.0".into()),
                            true,
                        );
                        return;
                    }
                    if !self.members.contains_key(&sender)
                        && self.members.len() >= self.room.as_ref().map_or(4, |r| r.capacity)
                    {
                        self.send(sender, Wire::Reject("房间已满".into()), true);
                        return;
                    }
                    let member = Member {
                        id: sender,
                        name: clean(&name, 24),
                    };
                    let fresh = self.members.insert(sender, member.clone()).is_none();
                    self.last_seen.insert(sender, Instant::now());
                    if let Some(room) = self.room.as_mut() {
                        room.players = self.members.len();
                    }
                    if let Some(room) = self.room.clone() {
                        self.send(
                            sender,
                            Wire::Welcome {
                                room,
                                members: self.members.values().cloned().collect(),
                            },
                            true,
                        );
                    }
                    if fresh && let Ok(json) = serde_json::to_string(&member) {
                        self.event("peer_join", sender, &json);
                    }
                    self.roster();
                }
                Wire::Input(input) if self.members.contains_key(&sender) && input.valid() => {
                    if let Ok(json) = serde_json::to_string(&input) {
                        self.event("input", sender, &json);
                    }
                }
                Wire::Action(action)
                    if self.members.contains_key(&sender)
                        && action.yaw.is_finite()
                        && action.pitch.is_finite()
                        && action.pitch.abs() <= 1.6 =>
                {
                    if let Ok(json) = serde_json::to_string(&action) {
                        self.event("action", sender, &json);
                    }
                }
                Wire::Leave => self.remove_member(sender),
                _ => {}
            }
        } else if self.role == Role::Client && sender == 1 {
            match message {
                Wire::Welcome { room, members } => {
                    let welcome = serde_json::to_string(&room).unwrap_or_default();
                    self.room = Some(room);
                    self.members = members.into_iter().map(|m| (m.id, m)).collect();
                    self.event("joined", self.local_id, &welcome);
                }
                Wire::Snapshot(data) => {
                    if let Ok(json) = serde_json::to_string(&data) {
                        self.event("snapshot", sender, &json);
                    }
                }
                Wire::Event { kind, data } => {
                    if kind == "roster"
                        && let Ok(members) = serde_json::from_value::<Vec<Member>>(data.clone())
                    {
                        self.members = members.into_iter().map(|m| (m.id, m)).collect();
                    }
                    if let Ok(json) = serde_json::to_string(&data) {
                        self.event(&kind, sender, &json);
                    }
                }
                Wire::Reject(reason) => {
                    self.close_peer();
                    self.event("error", 0, &reason);
                }
                _ => {}
            }
        }
    }
    fn roster(&mut self) {
        if let Ok(data) = serde_json::to_value(self.members.values().cloned().collect::<Vec<_>>()) {
            self.broadcast(
                Wire::Event {
                    kind: "roster".into(),
                    data,
                },
                true,
            );
        }
    }
    fn remove_member(&mut self, id: u32) {
        if self.members.remove(&id).is_some() {
            self.last_seen.remove(&id);
            self.event("peer_left", id, "{}");
            if let Some(r) = self.room.as_mut() {
                r.players = self.members.len();
            }
            self.roster();
        }
    }
    fn close_peer(&mut self) {
        if let Some(mut peer) = self.peer.take() {
            let _ = peer.try_call("close", &[]);
        }
        self.role = Role::Offline;
        self.local_id = 0;
        self.members.clear();
        self.last_seen.clear();
        self.room = None;
        self.beacon = None;
        self.hello_sent = false;
        self.disconnections.borrow_mut().clear();
        self.reassembly.pending.clear();
        self.events.clear();
    }
    fn poll_discovery(&mut self, dt: f64) {
        let mut requests = Vec::new();
        if let Some(socket) = &self.beacon {
            let mut buffer = [0u8; 1024];
            for _ in 0..32 {
                match socket.recv_from(&mut buffer) {
                    Ok((n, addr)) if &buffer[..n] == b"ASHFALL_DISCOVER_1" => requests.push(addr),
                    Ok(_) => {}
                    Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                    Err(_) => break,
                }
            }
        }
        if let (Some(socket), Some(room)) = (&self.beacon, &self.room)
            && let Ok(bytes) = serde_json::to_vec(room)
        {
            for addr in requests {
                let _ = socket.send_to(&bytes, addr);
            }
        }
        self.timer += dt;
        if let Some(socket) = &self.browser {
            if self.timer >= 1.0 {
                self.timer = 0.0;
                let _ = socket.send_to(
                    b"ASHFALL_DISCOVER_1",
                    SocketAddr::from(([255, 255, 255, 255], self.discovery_port)),
                );
                let _ = socket.send_to(
                    b"ASHFALL_DISCOVER_1",
                    SocketAddr::from(([127, 0, 0, 1], self.discovery_port)),
                );
            }
            let mut buffer = [0u8; 2048];
            for _ in 0..64 {
                match socket.recv_from(&mut buffer) {
                    Ok((n, addr)) => {
                        if let Ok(room) = serde_json::from_slice::<Room>(&buffer[..n])
                            && room.magic == "ASHFALL_LAN"
                            && room.protocol == PROTOCOL
                            && room.port > 0
                            && matches!(room.capacity, 4 | 10)
                            && room.players <= room.capacity
                        {
                            let key = room.room_id.clone();
                            let received_ip = addr.ip().to_string();
                            let ip = self
                                .rooms
                                .get(&key)
                                .filter(|old| {
                                    !old.ip.starts_with("127.") && addr.ip().is_loopback()
                                })
                                .map(|old| old.ip.clone())
                                .unwrap_or(received_ip);
                            self.rooms.insert(
                                key,
                                SeenRoom {
                                    room,
                                    ip,
                                    seen: Instant::now(),
                                },
                            );
                        }
                    }
                    Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                    Err(_) => break,
                }
            }
        }
        self.rooms
            .retain(|_, r| r.seen.elapsed() < Duration::from_secs(5));
    }
}

#[godot_api]
impl LanSession {
    #[func]
    fn start_discovery(&mut self) -> bool {
        match UdpSocket::bind("0.0.0.0:0") {
            Ok(socket) => {
                if socket.set_nonblocking(true).is_err() || socket.set_broadcast(true).is_err() {
                    return false;
                }
                self.browser = Some(socket);
                self.timer = 1.0;
                true
            }
            Err(_) => false,
        }
    }
    #[func]
    fn set_discovery_port(&mut self, port: i32) {
        if let Ok(p) = u16::try_from(port)
            && p > 0
        {
            self.discovery_port = p;
        }
    }
    #[func]
    fn host_room(&mut self, name: GString, nickname: GString, port: i32) -> GString {
        self.close_peer();
        let Ok(port) = u16::try_from(port) else {
            return "端口无效".into();
        };
        if port == 0 {
            return "端口无效".into();
        }
        let Ok(mut peer) = self.make_peer() else {
            return "无法创建 ENet".into();
        };
        let result = peer.try_call(
            "create_server",
            &[
                i64::from(port).to_variant(),
                16i64.to_variant(),
                3i64.to_variant(),
            ],
        );
        if result
            .ok()
            .and_then(|v| v.try_to::<i64>().ok())
            .is_none_or(|code| code != 0)
        {
            return "端口被占用或服务器创建失败".into();
        }
        self.peer = Some(peer);
        self.role = Role::Host;
        self.local_id = 1;
        let nick = clean(&nickname.to_string(), 24);
        self.members.insert(
            1,
            Member {
                id: 1,
                name: nick.clone(),
            },
        );
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        self.room = Some(Room {
            magic: "ASHFALL_LAN".into(),
            protocol: PROTOCOL,
            build: BUILD.into(),
            room_id: format!("{nonce:x}-{}", std::process::id()),
            name: clean(&name.to_string(), 48),
            host: nick,
            port,
            players: 1,
            capacity: 4,
            mode: "coop".into(),
            playing: false,
            stage: 0,
            wave: 0,
        });
        if let Ok(socket) = UdpSocket::bind(("0.0.0.0", self.discovery_port))
            && socket.set_nonblocking(true).is_ok()
        {
            self.beacon = Some(socket);
        }
        "".into()
    }
    #[func]
    fn join_room(&mut self, address: GString, nickname: GString, port: i32) -> GString {
        self.close_peer();
        let Ok(port) = u16::try_from(port) else {
            return "端口无效".into();
        };
        let Ok(mut peer) = self.make_peer() else {
            return "无法创建 ENet".into();
        };
        let result = peer.try_call(
            "create_client",
            &[
                address.to_variant(),
                i64::from(port).to_variant(),
                3i64.to_variant(),
            ],
        );
        if result
            .ok()
            .and_then(|v| v.try_to::<i64>().ok())
            .is_none_or(|code| code != 0)
        {
            return "无法连接指定地址".into();
        }
        self.peer = Some(peer);
        self.role = Role::Client;
        self.nickname = clean(&nickname.to_string(), 24);
        self.connecting_since = Instant::now();
        self.heartbeat = 0.0;
        "".into()
    }
    #[func]
    fn leave(&mut self) {
        if self.role == Role::Client {
            self.send(1, Wire::Leave, true);
        } else if self.role == Role::Host {
            self.broadcast(
                Wire::Event {
                    kind: "room_closed".into(),
                    data: serde_json::Value::Null,
                },
                true,
            );
        }
        if let Some(peer) = self.peer.as_mut()
            && let Ok(host) = peer.try_call("get_host", &[])
            && let Ok(mut host) = host.try_to::<Gd<Object>>()
        {
            let _ = host.try_call("flush", &[]);
        }
        self.close_peer();
    }
    #[func]
    fn role(&self) -> GString {
        match self.role {
            Role::Host => "host",
            Role::Client if self.room.is_some() => "client",
            Role::Client => "connecting",
            Role::Offline => "offline",
        }
        .into()
    }
    #[func]
    fn local_id(&self) -> i64 {
        i64::from(self.local_id)
    }
    #[func]
    fn members_json(&self) -> GString {
        serde_json::to_string(&self.members.values().collect::<Vec<_>>())
            .unwrap_or_default()
            .as_str()
            .into()
    }
    #[func]
    fn update_room(&mut self, stage: i32, wave: i32, playing: bool) {
        if let Some(r) = self.room.as_mut() {
            r.stage = stage;
            r.wave = wave;
            r.playing = playing;
        }
    }
    #[func]
    fn configure_pvp_room(&mut self) {
        if self.role == Role::Host
            && let Some(r) = self.room.as_mut()
        {
            r.capacity = 10;
            r.mode = "pvp".into();
            r.stage = 3;
        }
    }
    #[func]
    fn rooms_json(&self) -> GString {
        let list: Vec<_> = self
            .rooms
            .values()
            .map(|seen| {
                let mut v = serde_json::to_value(&seen.room).unwrap_or(serde_json::Value::Null);
                if let Some(map) = v.as_object_mut() {
                    map.insert("ip".into(), seen.ip.clone().into());
                    map.insert("compatible".into(), (seen.room.build == BUILD).into());
                }
                v
            })
            .collect();
        serde_json::to_string(&list)
            .unwrap_or_default()
            .as_str()
            .into()
    }
    #[func]
    fn drain_events(&mut self) -> Array<VarDictionary> {
        let mut out = Array::new();
        for e in self.events.drain(..) {
            let mut d = VarDictionary::new();
            d.set("kind", e.kind);
            d.set("peer", e.peer);
            d.set("data", e.data);
            out.push(&d);
        }
        out
    }
    #[func]
    fn send_input(&mut self, x: f32, z: f32, yaw: f32, pitch: f32, buttons: i32, seq: i64) {
        if let (Ok(buttons), Ok(seq)) = (u32::try_from(buttons), u64::try_from(seq)) {
            let input = InputFrame {
                x,
                z,
                yaw,
                pitch,
                buttons,
                seq,
            };
            if input.valid() && self.role == Role::Client {
                self.send(1, Wire::Input(input), false);
            }
        }
    }
    #[func]
    fn send_action(&mut self, kind: GString, arg: i32, seq: i64, yaw: f32, pitch: f32) {
        let Ok(kind) = serde_json::from_value::<ActionKind>(kind.to_string().into()) else {
            return;
        };
        let Ok(seq) = u64::try_from(seq) else {
            return;
        };
        if self.role == Role::Client && yaw.is_finite() && pitch.is_finite() {
            self.send(
                1,
                Wire::Action(Action {
                    kind,
                    arg,
                    seq,
                    yaw,
                    pitch,
                }),
                true,
            );
        }
    }
    #[func]
    fn send_snapshot(&mut self, json: GString, target: i64) {
        if self.role != Role::Host {
            return;
        }
        if let Ok(data) = serde_json::from_str(&json.to_string()) {
            if target == 0 {
                self.broadcast(Wire::Snapshot(data), false);
            } else if let Ok(target) = u32::try_from(target) {
                self.send(target, Wire::Snapshot(data), true);
            }
        }
    }
    #[func]
    fn send_event(&mut self, kind: GString, json: GString) {
        if self.role == Role::Host
            && let Ok(data) = serde_json::from_str(&json.to_string())
        {
            self.broadcast(
                Wire::Event {
                    kind: kind.to_string(),
                    data,
                },
                true,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn snapshots_reassemble_out_of_order_and_fit_mtu() {
        let bytes: Vec<u8> = (0..8000).map(|i| (i % 251) as u8).collect();
        let mut packets = fragment(&bytes, 7);
        assert!(packets.iter().all(|p| p.len() <= 1166));
        packets.reverse();
        let mut assembly = Assemblies::default();
        let mut completed = None;
        for p in &packets {
            if let Some(result) = assembly.push(1, p) {
                completed = Some(result);
            }
        }
        assert_eq!(completed, Some(bytes));
        assert!(assembly.pending.is_empty());
    }
    #[test]
    fn incomplete_and_malformed_fragments_are_bounded() {
        let mut a = Assemblies::default();
        assert!(a.push(1, b"AFF1").is_none());
        for transfer in 0..40 {
            let packets = fragment(&[0; 4000], transfer);
            assert!(a.push(1, &packets[0]).is_none());
        }
        assert!(a.pending.len() <= 16);
    }
    #[test]
    fn compressed_snapshot_round_trips() {
        let m = Wire::Snapshot(serde_json::json!({"epoch":1,"actors":[1,2,3]}));
        let bytes = encode(m, true).expect("fixture must encode");
        assert!(matches!(decode(&bytes), Ok(Wire::Snapshot(_))));
    }
    #[test]
    fn malformed_packets_and_nonfinite_input_are_rejected() {
        assert!(decode(b"AFN1\x04{} ").is_err());
        assert!(decode(&[0; 32]).is_err());
        assert!(
            !InputFrame {
                x: f32::NAN,
                z: 0.0,
                yaw: 0.0,
                pitch: 0.0,
                buttons: 0,
                seq: 1
            }
            .valid()
        );
    }
    #[test]
    fn unicode_names_are_bounded_without_splitting_utf8() {
        assert_eq!(clean("余烬\n禁区", 3), "余烬禁");
    }
}
