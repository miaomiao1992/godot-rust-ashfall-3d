//! Engine-independent, server-owned cooperative player state.
use crate::rules::WEAPONS;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct PeerId(pub u32);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Life {
    Spawning,
    Alive,
    Downed,
    Dead,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Survivor {
    pub id: PeerId,
    pub name: String,
    pub life: Life,
    pub hp: f32,
    pub max_hp: f32,
    pub damage_multiplier: f32,
    pub resistance: f32,
    pub reload_multiplier: f32,
    pub speed_bonus: f32,
    pub magazines: [i32; 5],
    pub reserves: [i32; 5],
    pub weapon: usize,
    pub points: i32,
    pub bleed: f32,
    pub revive: f32,
    pub reload: f32,
    pub reload_total: f32,
    pub stamina: f32,
    pub sprinting: bool,
    #[serde(skip)]
    exhausted: bool,
    #[serde(skip)]
    pub shot_cooldown: f32,
    #[serde(skip)]
    pub invulnerability: f32,
    #[serde(skip)]
    pub last_action: u64,
}

impl Survivor {
    fn new(id: PeerId, name: String, level: i32) -> Self {
        Self {
            id,
            name,
            life: Life::Alive,
            hp: 100.0,
            max_hp: 100.0,
            damage_multiplier: 1.0,
            resistance: 0.0,
            reload_multiplier: 1.0,
            speed_bonus: 0.0,
            magazines: [15, 36, 8, 30, 6],
            reserves: [999, 240, 56, 180, 36],
            weapon: 0,
            points: (level - 1).max(0),
            bleed: 0.0,
            revive: 0.0,
            reload: 0.0,
            reload_total: 1.0,
            stamina: 100.0,
            sprinting: false,
            exhausted: false,
            shot_cooldown: 0.0,
            invulnerability: 2.0,
            last_action: 0,
        }
    }
    pub fn tick(&mut self, dt: f32) {
        self.shot_cooldown = (self.shot_cooldown - dt).max(0.0);
        self.invulnerability = (self.invulnerability - dt).max(0.0);
        if self.life == Life::Downed {
            self.bleed = (self.bleed - dt).max(0.0);
            if self.bleed == 0.0 {
                self.life = Life::Dead;
                self.revive = 0.0;
            }
        }
        if self.reload > 0.0 {
            self.reload = (self.reload - dt).max(0.0);
            if self.reload == 0.0 {
                let need = WEAPONS[self.weapon].magazine - self.magazines[self.weapon];
                let amount = if self.weapon == 0 {
                    need
                } else {
                    need.min(self.reserves[self.weapon])
                };
                self.magazines[self.weapon] += amount;
                if self.weapon != 0 {
                    self.reserves[self.weapon] -= amount;
                }
            }
        }
    }
    pub fn fire(&mut self, sequence: u64) -> bool {
        if sequence <= self.last_action {
            return false;
        }
        self.last_action = sequence;
        if self.life != Life::Alive
            || self.reload > 0.0
            || self.shot_cooldown > 0.015
            || self.magazines[self.weapon] == 0
            || self.sprinting
        {
            return false;
        }
        self.magazines[self.weapon] -= 1;
        self.shot_cooldown = WEAPONS[self.weapon].rate;
        true
    }
    pub fn begin_reload(&mut self) -> bool {
        if self.life != Life::Alive
            || self.reload > 0.0
            || self.magazines[self.weapon] == WEAPONS[self.weapon].magazine
            || (self.weapon != 0 && self.reserves[self.weapon] == 0)
        {
            return false;
        }
        self.reload_total = WEAPONS[self.weapon].reload * self.reload_multiplier;
        self.reload = self.reload_total;
        true
    }
    pub fn damage(&mut self, amount: f32) -> bool {
        if !amount.is_finite()
            || amount <= 0.0
            || self.life != Life::Alive
            || self.invulnerability > 0.0
        {
            return false;
        }
        self.hp = (self.hp - amount * (1.0 - self.resistance)).max(0.0);
        self.invulnerability = 0.38;
        if self.hp == 0.0 {
            self.life = Life::Downed;
            self.bleed = 20.0;
            self.reload = 0.0;
        }
        true
    }
    pub fn upgrade(&mut self, index: i32) -> bool {
        if self.points == 0 || !(0..3).contains(&index) || self.life != Life::Alive {
            return false;
        }
        self.points -= 1;
        match index {
            0 => self.damage_multiplier += 0.18,
            1 => {
                self.max_hp += 20.0;
                self.resistance = (self.resistance + 0.04).min(0.4);
                self.hp = (self.hp + 45.0).min(self.max_hp);
            }
            _ => {
                self.reload_multiplier = (self.reload_multiplier * 0.88).max(0.4);
                self.speed_bonus += 0.25;
                self.resupply(true);
            }
        }
        true
    }
    pub fn movement(&mut self, x: f32, z: f32, sprint: bool, aim: bool, dt: f32) -> (f32, f32) {
        if ![x, z, dt].iter().all(|v| v.is_finite()) || self.life != Life::Alive {
            self.sprinting = false;
            return (0.0, 0.0);
        }
        if self.stamina <= 3.0 {
            self.exhausted = true;
        } else if self.stamina >= 25.0 {
            self.exhausted = false;
        }
        let length = (x * x + z * z).sqrt();
        self.sprinting = sprint && !aim && !self.exhausted && self.reload == 0.0 && length > 0.01;
        self.stamina = (self.stamina
            + (if self.sprinting { -28.0 } else { 19.0 }) * dt.clamp(0.0, 0.1))
        .clamp(0.0, 100.0);
        let speed = (if self.sprinting {
            9.2
        } else if aim {
            3.7
        } else {
            6.0
        }) + self.speed_bonus;
        if length > 0.001 {
            (x / length * speed, z / length * speed)
        } else {
            (0.0, 0.0)
        }
    }
    pub fn resupply(&mut self, full: bool) {
        for (i, w) in WEAPONS.iter().enumerate().skip(1) {
            self.reserves[i] = (self.reserves[i]
                + (w.reserve as f32 * if full { 0.55 } else { 0.14 }) as i32)
                .min(w.reserve);
        }
        if full && self.life == Life::Alive {
            self.hp = (self.hp + 18.0).min(self.max_hp);
        }
    }
}

#[derive(Default)]
pub struct Coop {
    pub players: BTreeMap<PeerId, Survivor>,
    revivers: BTreeMap<PeerId, PeerId>,
}
impl Coop {
    pub fn register(&mut self, id: PeerId, name: String, level: i32) {
        if self.players.len() < 4 && id.0 > 0 {
            self.players
                .entry(id)
                .or_insert_with(|| Survivor::new(id, name, level));
        }
    }
    pub fn tick(&mut self, dt: f32) {
        if dt.is_finite() && dt > 0.0 {
            for p in self.players.values_mut() {
                p.tick(dt.min(0.1));
            }
        }
    }
    pub fn revive(
        &mut self,
        actor: PeerId,
        target: PeerId,
        distance: f32,
        held: bool,
        dt: f32,
    ) -> bool {
        let eligible = actor != target
            && distance.is_finite()
            && distance <= 3.2
            && held
            && self
                .players
                .get(&actor)
                .is_some_and(|p| p.life == Life::Alive);
        let Some(victim) = self.players.get_mut(&target) else {
            return false;
        };
        if victim.life != Life::Downed {
            return false;
        }
        if !eligible {
            if self.revivers.get(&target) == Some(&actor) {
                victim.revive = 0.0;
                self.revivers.remove(&target);
            }
            return false;
        }
        if self.revivers.insert(target, actor) != Some(actor) {
            victim.revive = 0.0;
        }
        if dt.is_finite() && dt > 0.0 {
            victim.revive += dt.min(0.1);
        }
        if victim.revive >= 3.0 {
            victim.life = Life::Alive;
            victim.hp = victim.max_hp * 0.3;
            victim.bleed = 0.0;
            victim.revive = 0.0;
            victim.invulnerability = 2.0;
            self.revivers.remove(&target);
            return true;
        }
        false
    }
    pub fn wipe(&self) -> bool {
        !self.players.is_empty()
            && self
                .players
                .values()
                .all(|p| !matches!(p.life, Life::Alive | Life::Spawning))
    }
    pub fn respawn(&mut self) {
        for p in self.players.values_mut() {
            if matches!(p.life, Life::Downed | Life::Dead) {
                p.life = Life::Alive;
                p.hp = p.max_hp;
                p.bleed = 0.0;
                p.revive = 0.0;
                p.invulnerability = 2.0;
            }
            p.resupply(true);
        }
        self.revivers.clear();
    }
    pub fn remove(&mut self, id: PeerId) {
        self.players.remove(&id);
        self.revivers
            .retain(|target, actor| *target != id && *actor != id);
        for p in self.players.values_mut() {
            p.revive = 0.0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn late_join_gets_points_but_upgrade_is_personal() {
        let mut c = Coop::default();
        c.register(PeerId(1), "A".into(), 5);
        c.register(PeerId(2), "B".into(), 5);
        assert!(c.players.get_mut(&PeerId(1)).is_some_and(|p| p.upgrade(1)));
        assert_eq!(c.players[&PeerId(1)].max_hp, 120.0);
        assert_eq!(c.players[&PeerId(2)].max_hp, 100.0);
    }
    #[test]
    fn shot_sequence_and_ammo_cannot_be_replayed() {
        let mut p = Survivor::new(PeerId(1), "A".into(), 1);
        assert!(p.fire(1));
        assert!(!p.fire(1));
        assert!(!p.fire(2));
        p.tick(0.3);
        assert!(p.fire(3));
        assert_eq!(p.magazines[0], 13);
    }
    #[test]
    fn bleed_out_and_revival_are_authoritative() {
        let mut c = Coop::default();
        c.register(PeerId(1), "A".into(), 1);
        c.register(PeerId(2), "B".into(), 1);
        if let Some(p) = c.players.get_mut(&PeerId(2)) {
            p.invulnerability = 0.0;
            assert!(p.damage(1000.0));
        }
        assert!(!c.wipe());
        for _ in 0..31 {
            c.revive(PeerId(1), PeerId(2), 2.0, true, 0.1);
        }
        assert_eq!(c.players[&PeerId(2)].life, Life::Alive);
        assert!((c.players[&PeerId(2)].hp - 30.0).abs() < 0.001);
        if let Some(p) = c.players.get_mut(&PeerId(2)) {
            p.invulnerability = 0.0;
            p.damage(1000.0);
        }
        for _ in 0..210 {
            c.tick(0.1);
        }
        assert_eq!(c.players[&PeerId(2)].life, Life::Dead);
    }
    #[test]
    fn room_population_and_invalid_damage_are_bounded() {
        let mut c = Coop::default();
        for id in 1..=8 {
            c.register(PeerId(id), "A".into(), 1);
        }
        assert_eq!(c.players.len(), 4);
        let Some(p) = c.players.get_mut(&PeerId(1)) else {
            panic!("fixture missing");
        };
        p.invulnerability = 0.0;
        assert!(!p.damage(f32::NAN));
        assert_eq!(p.hp, 100.0);
    }
}
