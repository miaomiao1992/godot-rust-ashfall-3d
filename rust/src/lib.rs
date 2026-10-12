mod coop;
mod network;
mod pvp;
mod rules;
mod tactics;

use godot::classes::{IRefCounted, RefCounted};
use godot::prelude::*;

struct AshfallExtension;
#[gdextension]
unsafe impl ExtensionLibrary for AshfallExtension {}

// Zig's COFF driver does not consume rustc's GNU .def switch. Keep the Godot
// entry point explicitly exported through the standard PE linker directive.
#[cfg(target_os = "windows")]
#[used]
#[unsafe(link_section = ".drectve")]
static GODOT_DLL_EXPORT: [u8; 25] = *b" /EXPORT:gdext_rust_init ";

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct AshfallCore {
    run: rules::Run,
    crowd: Vec<Vector3>,
    goals: tactics::SectorGoals,
    coop: coop::Coop,
    pvp: pvp::Pvp,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for AshfallCore {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            run: rules::Run::default(),
            crowd: Vec::new(),
            goals: tactics::SectorGoals::default(),
            coop: coop::Coop::default(),
            pvp: pvp::Pvp::default(),
            base,
        }
    }
}

#[godot_api]
impl AshfallCore {
    #[func]
    fn reset_run(&mut self) {
        self.run = rules::Run::default();
        self.crowd.clear();
        self.goals = tactics::SectorGoals::default();
        self.coop = coop::Coop::default();
        self.pvp = pvp::Pvp::default();
    }

    #[func]
    fn snapshot(&self) -> VarDictionary {
        let r = &self.run;
        let mut d = VarDictionary::new();
        d.set("wave", r.wave);
        d.set("stage", r.stage());
        d.set("stage_wave", r.stage_wave());
        d.set("level", r.level);
        d.set("xp", r.xp);
        d.set("xp_needed", r.xp_needed);
        d.set("kills", r.kills);
        d.set("headshots", r.headshots);
        d.set("damage_multiplier", r.damage_multiplier);
        d.set("max_hp", r.max_hp);
        d.set("resistance", r.resistance);
        d.set("reload_multiplier", r.reload_multiplier);
        d.set("speed_bonus", r.speed_bonus);
        d
    }

    #[func]
    fn advance_wave(&mut self) -> VarDictionary {
        self.run.advance_wave();
        let mut d = self.snapshot();
        let party = self.coop.players.len().max(1);
        d.set(
            "budget",
            (self.run.budget() as f32 * (1.0 + 0.5 * (party - 1) as f32)).round() as i32,
        );
        d.set("boss", self.run.stage_wave() == 3);
        d.set("stage_name", rules::STAGES[self.run.stage() as usize]);
        d.set("boss_name", rules::BOSSES[self.run.stage() as usize]);
        d
    }

    #[func]
    fn weapons(&self) -> Array<VarDictionary> {
        let mut result = Array::new();
        for w in &rules::WEAPONS {
            let mut d = VarDictionary::new();
            d.set("name", w.name);
            d.set("short", w.short);
            d.set("sound", w.sound);
            d.set("level", w.level);
            d.set("damage", w.damage);
            d.set("rate", w.rate);
            d.set("mag", w.magazine);
            d.set("reserve", w.reserve);
            d.set("reload", w.reload);
            d.set("pellets", w.pellets);
            d.set("spread", w.spread);
            d.set("kick", w.recoil);
            d.set("force", w.force);
            d.set("auto", w.automatic);
            result.push(&d);
        }
        result
    }

    #[func]
    fn monster_stats(&self, kind: i32, wave: i32) -> VarDictionary {
        let mut m = rules::monster(kind, wave);
        m.hp *= 1.0 + 0.3 * self.coop.players.len().max(1).saturating_sub(1) as f32;
        let mut d = VarDictionary::new();
        d.set("name", m.name);
        d.set("tier", m.tier);
        d.set("hp", m.hp);
        d.set("speed", m.speed);
        d.set("damage", m.damage);
        d.set("scale", m.scale);
        d
    }

    #[func]
    fn spawn_kind(&self, wave: i32, roll: f32) -> i32 {
        rules::spawn_kind(wave, roll)
    }

    #[func]
    fn hit_damage(&self, kind: i32, base: f32, head: bool) -> f32 {
        rules::hit_damage(kind, base, head)
    }

    #[func]
    fn player_damage(&self, hp: f32, damage: f32, resistance: f32) -> f32 {
        (hp - damage.max(0.0) * (1.0 - resistance.clamp(0.0, 0.4))).max(0.0)
    }

    #[func]
    fn register_kill(&mut self, kind: i32, head: bool) -> VarDictionary {
        let (reward, levels) = self.run.reward(kind, head);
        for player in self.coop.players.values_mut() {
            player.points += levels;
        }
        let mut d = self.snapshot();
        d.set("reward", reward);
        d.set("levels_gained", levels);
        d
    }

    #[func]
    fn apply_upgrade(&mut self, index: i32) -> VarDictionary {
        let heal = self.run.upgrade(index);
        let mut d = self.snapshot();
        d.set("heal", heal);
        d
    }

    #[func]
    fn boss_action(&self, stage: i32, distance: f32, step: i32, enraged: bool) -> GString {
        rules::boss_action(stage, distance, step, enraged).into()
    }

    #[func]
    fn acid_pattern(&self, stage: i32, step: i32, elite: bool) -> VarDictionary {
        let p = tactics::acid_pattern(stage, step, elite);
        let mut spots = Array::<Vector3>::new();
        for spot in &p.spots {
            // x=lateral offset, y=activation stagger, z=forward offset.
            spots.push(Vector3::new(spot.lateral, spot.delay, spot.forward));
        }
        let mut d = VarDictionary::new();
        d.set("name", p.name);
        d.set("hint", p.hint);
        d.set("radius", p.radius);
        d.set("warning", p.warning);
        d.set("active", p.active);
        d.set("spots", &spots);
        d
    }

    #[func]
    fn encounter(&self, stage: i32, wave: i32, cursor: i32, gates: i32) -> VarDictionary {
        let mut d = VarDictionary::new();
        d.set("gate", tactics::gate_index(stage, wave, cursor, gates));
        d.set("interval", tactics::spawn_interval(stage, wave, cursor + 1));
        d.set("max_spitters", if stage == 1 { 2 } else { 1 });
        d
    }

    #[func]
    fn reset_sector_goals(&mut self) {
        self.goals = tactics::SectorGoals::default();
    }

    #[func]
    fn activate_terminal(&mut self, index: i32) -> bool {
        self.goals.activate(index)
    }

    #[func]
    fn objective_progress(&self) -> i32 {
        self.goals.count()
    }

    #[func]
    fn objective_required(&self, stage: i32, stage_wave: i32) -> i32 {
        tactics::objective_required(stage, stage_wave)
    }

    #[func]
    fn reactor_damage_factor(&self, stage: i32) -> f32 {
        tactics::reactor_damage_factor(stage, self.goals.count())
    }

    #[func]
    fn coop_register(&mut self, id: i64, name: GString) {
        if let Ok(id) = u32::try_from(id) {
            if self.pvp.enabled && !self.pvp.register(coop::PeerId(id), name.to_string()) {
                return;
            }
            if self.pvp.enabled {
                self.coop
                    .players
                    .retain(|id, _| self.pvp.fighters.contains_key(id));
            }
            self.coop
                .register(coop::PeerId(id), name.to_string(), self.run.level);
            if self.pvp.enabled
                && let Some(p) = self.coop.players.get_mut(&coop::PeerId(id))
            {
                p.points = 0;
            }
            if self.pvp.started {
                self.pvp.refill_bots(&mut self.coop);
            }
        }
    }
    #[func]
    fn coop_remove(&mut self, id: i64) {
        if let Ok(id) = u32::try_from(id) {
            self.coop.remove(coop::PeerId(id));
            self.pvp.fighters.remove(&coop::PeerId(id));
            if self.pvp.started {
                self.pvp.refill_bots(&mut self.coop);
            }
        }
    }
    #[func]
    fn coop_loading(&mut self, id: i64) {
        if let Ok(id) = u32::try_from(id)
            && let Some(p) = self.coop.players.get_mut(&coop::PeerId(id))
        {
            p.life = coop::Life::Spawning;
        }
    }
    #[func]
    fn coop_activate(&mut self, id: i64) {
        if let Ok(id) = u32::try_from(id)
            && let Some(p) = self.coop.players.get_mut(&coop::PeerId(id))
            && p.life == coop::Life::Spawning
        {
            p.life = coop::Life::Alive;
            p.invulnerability = 2.0;
        }
    }
    #[func]
    fn coop_tick(&mut self, dt: f32) {
        if self.pvp.enabled {
            if dt.is_finite() && dt > 0.0 {
                for player in self.coop.players.values_mut() {
                    player.tick(dt);
                }
            }
            self.pvp.tick(&mut self.coop, dt);
        } else {
            self.coop.tick(dt);
        }
    }
    #[func]
    fn coop_velocity(
        &mut self,
        id: i64,
        direction: Vector3,
        sprint: bool,
        aim: bool,
        dt: f32,
    ) -> Vector3 {
        let Ok(id) = u32::try_from(id) else {
            return Vector3::ZERO;
        };
        let Some(player) = self.coop.players.get_mut(&coop::PeerId(id)) else {
            return Vector3::ZERO;
        };
        let (x, z) = player.movement(direction.x, direction.z, sprint, aim, dt);
        Vector3::new(x, 0.0, z)
    }
    #[func]
    fn coop_target(
        &self,
        ids: PackedInt64Array,
        positions: Array<Vector3>,
        origin: Vector3,
    ) -> i64 {
        let mut best = 0;
        let mut distance = f32::INFINITY;
        for (id, position) in ids.as_slice().iter().zip(positions.iter_shared()) {
            let Ok(peer) = u32::try_from(*id) else {
                continue;
            };
            if self
                .coop
                .players
                .get(&coop::PeerId(peer))
                .is_some_and(|p| p.life == coop::Life::Alive)
            {
                let d = position.distance_squared_to(origin);
                if d < distance {
                    distance = d;
                    best = *id;
                }
            }
        }
        best
    }
    #[func]
    fn coop_players_json(&self) -> GString {
        serde_json::to_string(&self.coop.players.values().collect::<Vec<_>>())
            .unwrap_or_default()
            .as_str()
            .into()
    }
    #[func]
    fn coop_fire(&mut self, id: i64, seq: i64) -> bool {
        let (Ok(id), Ok(seq)) = (u32::try_from(id), u64::try_from(seq)) else {
            return false;
        };
        self.coop
            .players
            .get_mut(&coop::PeerId(id))
            .is_some_and(|p| p.fire(seq))
    }
    #[func]
    fn coop_reload(&mut self, id: i64) -> bool {
        let Ok(id) = u32::try_from(id) else {
            return false;
        };
        self.coop
            .players
            .get_mut(&coop::PeerId(id))
            .is_some_and(|p| p.begin_reload())
    }
    #[func]
    fn coop_switch(&mut self, id: i64, index: i32) -> bool {
        let (Ok(id), Ok(index)) = (u32::try_from(id), usize::try_from(index)) else {
            return false;
        };
        let Some(w) = rules::WEAPONS.get(index) else {
            return false;
        };
        if !self.pvp.enabled && self.run.level < w.level {
            return false;
        }
        let Some(p) = self.coop.players.get_mut(&coop::PeerId(id)) else {
            return false;
        };
        if p.life != coop::Life::Alive {
            return false;
        }
        p.weapon = index;
        p.reload = 0.0;
        true
    }
    #[func]
    fn coop_damage(&mut self, id: i64, amount: f32) -> bool {
        let Ok(id) = u32::try_from(id) else {
            return false;
        };
        self.coop
            .players
            .get_mut(&coop::PeerId(id))
            .is_some_and(|p| p.damage(amount))
    }
    #[func]
    fn coop_upgrade(&mut self, id: i64, index: i32) -> bool {
        if self.pvp.enabled {
            return false;
        }
        let Ok(id) = u32::try_from(id) else {
            return false;
        };
        self.coop
            .players
            .get_mut(&coop::PeerId(id))
            .is_some_and(|p| p.upgrade(index))
    }
    #[func]
    fn coop_revive(&mut self, actor: i64, target: i64, distance: f32, held: bool, dt: f32) -> bool {
        let (Ok(actor), Ok(target)) = (u32::try_from(actor), u32::try_from(target)) else {
            return false;
        };
        self.coop.revive(
            coop::PeerId(actor),
            coop::PeerId(target),
            distance,
            held,
            dt,
        )
    }
    #[func]
    fn coop_wipe(&self) -> bool {
        self.coop.wipe()
    }
    #[func]
    fn coop_respawn(&mut self) {
        self.coop.respawn();
    }
    #[func]
    fn coop_resupply(&mut self, id: i64, full: bool) {
        if let Ok(id) = u32::try_from(id)
            && let Some(p) = self.coop.players.get_mut(&coop::PeerId(id))
        {
            p.resupply(full);
        }
    }
    #[func]
    fn coop_heal(&mut self, id: i64, amount: f32) {
        if amount.is_finite()
            && amount > 0.0
            && let Ok(id) = u32::try_from(id)
            && let Some(p) = self.coop.players.get_mut(&coop::PeerId(id))
            && p.life == coop::Life::Alive
        {
            p.hp = (p.hp + amount).min(p.max_hp);
        }
    }

    #[func]
    fn pvp_configure(&mut self) {
        self.reset_run();
        self.pvp.enabled = true;
        self.pvp.fill_bots = true;
        self.pvp.winner = -1;
        self.coop.capacity = 10;
    }
    #[func]
    fn penetration_limit(&self, weapon: i32, surface: GString) -> f32 {
        usize::try_from(weapon).map_or(0.0, |w| rules::penetration_limit(w, &surface.to_string()))
    }
    #[func]
    fn penetration_factor(&self, weapon: i32, surface: GString, thickness: f32) -> f32 {
        usize::try_from(weapon).map_or(0.0, |w| {
            rules::penetration_factor(w, &surface.to_string(), thickness)
        })
    }
    #[func]
    fn blast_cover_limit(&self, surface: GString) -> f32 {
        rules::blast_cover_limit(&surface.to_string())
    }
    #[func]
    fn blast_cover_factor(&self, surface: GString, thickness: f32) -> f32 {
        rules::blast_cover_factor(&surface.to_string(), thickness)
    }
    #[func]
    fn pvp_start(&mut self) {
        self.pvp.refill_bots(&mut self.coop);
        self.pvp.start(&mut self.coop);
    }
    #[func]
    fn pvp_set_fill_bots(&mut self, enabled: bool) {
        if !self.pvp.started {
            self.pvp.fill_bots = enabled;
        }
    }
    #[func]
    fn pvp_fill_bots(&mut self) {
        self.pvp.refill_bots(&mut self.coop);
    }
    #[func]
    fn pvp_team(&mut self, id: i64, team: i32) -> bool {
        let (Ok(id), Ok(team)) = (u32::try_from(id), usize::try_from(team)) else {
            return false;
        };
        self.pvp.choose_team(coop::PeerId(id), team)
    }
    #[func]
    fn pvp_join_team(&mut self, id: i64, team: i32) -> bool {
        let (Ok(id), Ok(team)) = (u32::try_from(id), usize::try_from(team)) else {
            return false;
        };
        self.pvp.join_team(&mut self.coop, coop::PeerId(id), team)
    }
    #[func]
    fn pvp_json(&self) -> GString {
        serde_json::to_string(&self.pvp)
            .unwrap_or_default()
            .as_str()
            .into()
    }
    #[func]
    fn pvp_throw(&mut self, id: i64, kind: i32, seq: i64) -> bool {
        let (Ok(id), Ok(kind), Ok(seq)) =
            (u32::try_from(id), usize::try_from(kind), u64::try_from(seq))
        else {
            return false;
        };
        let peer = coop::PeerId(id);
        if !self.pvp.throw(&self.coop, peer, kind, seq) {
            return false;
        }
        if let Some(p) = self.coop.players.get_mut(&peer) {
            p.last_action = seq;
        }
        true
    }
    #[func]
    fn pvp_flash(&mut self, id: i64, seconds: f32) {
        if seconds.is_finite()
            && seconds > 0.0
            && let Ok(id) = u32::try_from(id)
            && let Some(f) = self.pvp.fighters.get_mut(&coop::PeerId(id))
        {
            f.flash = f.flash.max(seconds.min(4.0));
        }
    }
    #[func]
    fn pvp_hit(&mut self, attacker: i64, victim: i64, amount: f32, head: bool) -> VarDictionary {
        let mut d = VarDictionary::new();
        let result = match (u32::try_from(attacker), u32::try_from(victim)) {
            (Ok(a), Ok(v)) => self.pvp.hit(
                &mut self.coop,
                coop::PeerId(a),
                coop::PeerId(v),
                amount,
                head,
            ),
            _ => (false, false),
        };
        d.set("hit", result.0);
        d.set("killed", result.1);
        d.set("head", head && result.0);
        d
    }

    #[func]
    fn steer(&self, direction: Vector3, speed: f32, flinch: f32, knockback: Vector3) -> Vector3 {
        let horizontal = Vector3::new(direction.x, 0.0, direction.z);
        let movement = if horizontal.length_squared() > 0.0001 {
            horizontal.normalized()
        } else {
            Vector3::ZERO
        };
        movement * speed * (1.0 - flinch.clamp(0.0, 1.0) * 0.8) + knockback
    }

    #[func]
    fn update_crowd(&mut self, positions: Array<Vector3>) {
        self.crowd.clear();
        self.crowd.extend(positions.iter_shared());
    }

    #[func]
    fn separation(&self, position: Vector3, radius: f32) -> Vector3 {
        let mut force = Vector3::ZERO;
        for other in &self.crowd {
            let offset = Vector3::new(position.x - other.x, 0.0, position.z - other.z);
            let distance_sq = offset.length_squared();
            if distance_sq > 0.0001 && distance_sq < radius * radius {
                let distance = distance_sq.sqrt();
                force += offset / distance * (1.0 - distance / radius);
            }
        }
        if force.length_squared() > 1.0 {
            force.normalized()
        } else {
            force
        }
    }
}
