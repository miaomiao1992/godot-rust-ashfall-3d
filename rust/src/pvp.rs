//! Host-authoritative 5v5 team deathmatch, sharing weapon and movement state.
use crate::coop::{Coop, Life, PeerId, Survivor};
use serde::Serialize;
use std::collections::BTreeMap;

pub const TEAM_SIZE: usize = 5;
pub const SCORE_LIMIT: u32 = 50;
pub const MATCH_SECONDS: f32 = 600.0;
pub const RESPAWN_SECONDS: f32 = 5.0;
pub const BOT_BASE: u32 = 4_000_000_000;

#[derive(Clone, Debug, Serialize)]
pub struct Fighter {
    pub id: PeerId,
    pub name: String,
    pub team: usize,
    pub is_bot: bool,
    pub kills: u32,
    pub deaths: u32,
    pub headshots: u32,
    pub respawn: f32,
    pub generation: u32,
    pub grenades: [u32; 3],
    pub flash: f32,
    #[serde(skip)]
    throw_cooldown: f32,
}

#[derive(Default, Serialize)]
pub struct Pvp {
    pub enabled: bool,
    pub started: bool,
    pub fill_bots: bool,
    pub remaining: f32,
    pub scores: [u32; 2],
    // -1 = in progress, 0/1 = winning team, 2 = draw.
    pub winner: i32,
    pub fighters: BTreeMap<PeerId, Fighter>,
}
impl Pvp {
    pub fn register(&mut self, id: PeerId, name: String) -> bool {
        if id.0 == 0 {
            return false;
        }
        if self.fighters.contains_key(&id) {
            return true;
        }
        let mut humans = [0, 0];
        for f in self.fighters.values().filter(|f| !f.is_bot) {
            humans[f.team] += 1;
        }
        let mut team = usize::from(humans[0] > humans[1]);
        if self.counts()[team] >= TEAM_SIZE {
            if let Some(bot) = self
                .fighters
                .values()
                .find(|f| f.is_bot && f.team == team)
                .map(|f| f.id)
            {
                self.fighters.remove(&bot);
            } else {
                team = 1 - team;
                if self.counts()[team] >= TEAM_SIZE {
                    return false;
                }
            }
        }
        self.fighters.insert(
            id,
            Fighter {
                id,
                name,
                team,
                is_bot: false,
                kills: 0,
                deaths: 0,
                headshots: 0,
                respawn: 0.0,
                generation: 0,
                grenades: [2, 2, 1],
                flash: 0.0,
                throw_cooldown: 0.0,
            },
        );
        true
    }
    pub fn refill_bots(&mut self, coop: &mut Coop) {
        if !self.fill_bots {
            return;
        }
        let mut humans = [0_usize, 0];
        for f in self.fighters.values().filter(|f| !f.is_bot) {
            humans[f.team] += 1;
        }
        let target = humans[0].max(humans[1]).clamp(1, TEAM_SIZE);
        for team in 0..2 {
            while self.counts()[team] > target {
                let Some(id) = self
                    .fighters
                    .values()
                    .find(|f| f.is_bot && f.team == team)
                    .map(|f| f.id)
                else {
                    break;
                };
                self.fighters.remove(&id);
            }
            while self.counts()[team] < target {
                let Some(id) = (0..TEAM_SIZE as u32)
                    .map(|slot| PeerId(BOT_BASE + team as u32 * 100 + slot))
                    .find(|id| !self.fighters.contains_key(id))
                else {
                    break;
                };
                let name = format!(
                    "[BOT] {}-{}",
                    if team == 0 { "R" } else { "B" },
                    id.0 % 100 + 1
                );
                // Bot placement is explicit, not the human team-balancing path.
                self.fighters.insert(
                    id,
                    Fighter {
                        id,
                        name: name.clone(),
                        team,
                        is_bot: true,
                        kills: 0,
                        deaths: 0,
                        headshots: 0,
                        respawn: 0.0,
                        generation: 0,
                        grenades: [2, 2, 1],
                        flash: 0.0,
                        throw_cooldown: 0.0,
                    },
                );
                let mut player = Survivor::new(id, name, 1);
                player.weapon = 3;
                coop.players.insert(id, player);
            }
        }
        coop.players.retain(|id, _| self.fighters.contains_key(id));
    }
    pub fn counts(&self) -> [usize; 2] {
        let mut counts = [0, 0];
        for p in self.fighters.values() {
            counts[p.team] += 1;
        }
        counts
    }
    pub fn choose_team(&mut self, id: PeerId, team: usize) -> bool {
        if self.started || team > 1 {
            return false;
        }
        if self.fighters.get(&id).is_some_and(|p| p.team == team) {
            return true;
        }
        if self.counts()[team] >= TEAM_SIZE {
            return false;
        }
        let Some(p) = self.fighters.get_mut(&id) else {
            return false;
        };
        p.team = team;
        true
    }
    pub fn start(&mut self, coop: &mut Coop) {
        self.started = true;
        self.remaining = MATCH_SECONDS;
        self.scores = [0, 0];
        self.winner = -1;
        coop.players.clear();
        coop.capacity = 10;
        for f in self.fighters.values_mut() {
            f.kills = 0;
            f.deaths = 0;
            f.headshots = 0;
            f.respawn = 0.0;
            f.generation += 1;
            f.grenades = [2, 2, 1];
            f.flash = 0.0;
            f.throw_cooldown = 0.0;
            let mut p = Survivor::new(f.id, f.name.clone(), 1);
            p.weapon = 3;
            coop.players.insert(f.id, p);
        }
    }
    pub fn tick(&mut self, coop: &mut Coop, dt: f32) -> Vec<PeerId> {
        let mut respawned = Vec::new();
        if !self.started || self.winner != -1 || !dt.is_finite() || dt <= 0.0 {
            return respawned;
        }
        self.remaining = (self.remaining - dt).max(0.0);
        for f in self.fighters.values_mut() {
            f.flash = (f.flash - dt).max(0.0);
            f.throw_cooldown = (f.throw_cooldown - dt).max(0.0);
            if f.respawn <= 0.0 {
                continue;
            }
            f.respawn = (f.respawn - dt).max(0.0);
            if f.respawn == 0.0
                && let Some(p) = coop.players.get_mut(&f.id)
            {
                let seq = p.last_action;
                let weapon = p.weapon;
                *p = Survivor::new(f.id, f.name.clone(), 1);
                p.last_action = seq;
                p.weapon = weapon;
                f.generation += 1;
                f.grenades = [2, 2, 1];
                f.flash = 0.0;
                f.throw_cooldown = 0.0;
                respawned.push(f.id);
            }
        }
        if self.remaining == 0.0 {
            self.finish();
        }
        respawned
    }
    pub fn hit(
        &mut self,
        coop: &mut Coop,
        attacker: PeerId,
        victim: PeerId,
        damage: f32,
        head: bool,
    ) -> (bool, bool) {
        if !self.started
            || self.winner != -1
            || attacker == victim
            || !damage.is_finite()
            || damage <= 0.0
        {
            return (false, false);
        }
        let (Some(a), Some(v)) = (self.fighters.get(&attacker), self.fighters.get(&victim)) else {
            return (false, false);
        };
        if a.team == v.team {
            return (false, false);
        }
        let team = a.team;
        let Some(p) = coop.players.get_mut(&victim) else {
            return (false, false);
        };
        if p.life != Life::Alive || p.invulnerability > 0.0 {
            return (false, false);
        }
        // PvP has no PvE per-hit immunity; only spawn protection applies.
        p.hp = (p.hp - damage * if head { 2.0 } else { 1.0 }).max(0.0);
        if p.hp > 0.0 {
            return (true, false);
        }
        p.life = Life::Dead;
        p.reload = 0.0;
        p.sprinting = false;
        if let Some(v) = self.fighters.get_mut(&victim) {
            v.deaths += 1;
            v.respawn = RESPAWN_SECONDS;
        }
        if let Some(a) = self.fighters.get_mut(&attacker) {
            a.kills += 1;
            a.headshots += u32::from(head);
        }
        self.scores[team] += 1;
        if self.scores[team] >= SCORE_LIMIT {
            self.finish();
        }
        (true, true)
    }
    fn finish(&mut self) {
        self.winner = if self.scores[0] > self.scores[1] {
            0
        } else if self.scores[1] > self.scores[0] {
            1
        } else {
            2
        };
    }
    pub fn throw(&mut self, coop: &Coop, id: PeerId, kind: usize, seq: u64) -> bool {
        if !self.started
            || self.winner != -1
            || kind > 2
            || !coop.players.get(&id).is_some_and(|p| p.life == Life::Alive)
        {
            return false;
        }
        let Some(f) = self.fighters.get_mut(&id) else {
            return false;
        };
        let Some(p) = coop.players.get(&id) else {
            return false;
        };
        if seq <= p.last_action || f.throw_cooldown > 0.0 || f.grenades[kind] == 0 {
            return false;
        }
        f.grenades[kind] -= 1;
        f.throw_cooldown = 1.0;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> (Pvp, Coop) {
        let mut pvp = Pvp {
            enabled: true,
            ..Default::default()
        };
        for id in 1..=10 {
            assert!(pvp.register(PeerId(id), format!("P{id}")));
        }
        let mut coop = Coop::default();
        pvp.start(&mut coop);
        for p in coop.players.values_mut() {
            p.invulnerability = 0.0;
        }
        (pvp, coop)
    }
    #[test]
    fn teams_have_five_slots_and_lobby_changes_are_bounded() {
        let (mut p, _) = fixture();
        assert_eq!(p.counts(), [5, 5]);
        assert!(!p.register(PeerId(11), "full".into()));
        assert!(!p.choose_team(PeerId(1), 1));
        p.started = false;
        p.fighters.remove(&PeerId(2));
        assert!(p.choose_team(PeerId(1), 1));
        assert_eq!(p.counts(), [4, 5]);
    }
    #[test]
    fn friendly_fire_invalid_hits_and_duplicate_deaths_do_not_score() {
        let (mut p, mut c) = fixture();
        assert_eq!(
            p.hit(&mut c, PeerId(1), PeerId(3), 999.0, false),
            (false, false)
        );
        assert_eq!(
            p.hit(&mut c, PeerId(1), PeerId(2), f32::NAN, false),
            (false, false)
        );
        assert_eq!(
            p.hit(&mut c, PeerId(1), PeerId(2), 50.0, true),
            (true, true)
        );
        assert_eq!(
            p.hit(&mut c, PeerId(1), PeerId(2), 999.0, false),
            (false, false)
        );
        assert_eq!(p.scores, [1, 0]);
        assert_eq!(p.fighters[&PeerId(2)].deaths, 1);
        assert_eq!(c.players[&PeerId(2)].life, Life::Dead);
    }
    #[test]
    fn respawn_restores_loadout_preserves_replay_guard_and_protects_spawn() {
        let (mut p, mut c) = fixture();
        c.players.get_mut(&PeerId(2)).unwrap().last_action = 99;
        p.hit(&mut c, PeerId(1), PeerId(2), 100.0, false);
        for _ in 0..49 {
            assert!(p.tick(&mut c, 0.1).is_empty());
        }
        for _ in 0..2 {
            p.tick(&mut c, 0.1);
        }
        let v = &c.players[&PeerId(2)];
        assert_eq!(v.life, Life::Alive);
        assert_eq!(v.hp, 100.0);
        assert_eq!(v.weapon, 3);
        assert_eq!(v.last_action, 99);
        assert_eq!(p.fighters[&PeerId(2)].generation, 2);
        assert_eq!(
            p.hit(&mut c, PeerId(1), PeerId(2), 999.0, false),
            (false, false)
        );
    }
    #[test]
    fn score_limit_timeout_and_restart_are_deterministic() {
        let (mut p, mut c) = fixture();
        p.scores = [49, 0];
        assert_eq!(
            p.hit(&mut c, PeerId(1), PeerId(2), 100.0, false),
            (true, true)
        );
        assert_eq!(p.winner, 0);
        p.start(&mut c);
        assert_eq!(p.scores, [0, 0]);
        p.remaining = 0.05;
        p.tick(&mut c, 0.1);
        assert_eq!(p.winner, 2);
    }
    #[test]
    fn grenade_inventory_cooldown_and_dead_throw_are_enforced() {
        let (mut p, mut c) = fixture();
        assert!(p.throw(&c, PeerId(1), 2, 1));
        assert!(!p.throw(&c, PeerId(1), 2, 2));
        assert!(!p.throw(&c, PeerId(1), 0, 3));
        for _ in 0..11 {
            p.tick(&mut c, 0.1);
        }
        assert!(p.throw(&c, PeerId(1), 0, 4));
        c.players.get_mut(&PeerId(1)).unwrap().life = Life::Dead;
        assert!(!p.throw(&c, PeerId(1), 1, 5));
    }

    #[test]
    fn slow_frames_do_not_extend_match_respawn_or_grenade_timers() {
        let (mut p, mut c) = fixture();
        assert!(p.throw(&c, PeerId(1), 0, 1));
        p.hit(&mut c, PeerId(1), PeerId(2), 100.0, false);
        assert_eq!(p.tick(&mut c, 5.1), vec![PeerId(2)]);
        assert!((p.remaining - (MATCH_SECONDS - 5.1)).abs() < 0.001);
        assert!(p.throw(&c, PeerId(1), 0, 2));
        // A grenade already in flight can still score after its owner dies.
        c.players.get_mut(&PeerId(1)).unwrap().life = Life::Dead;
        c.players.get_mut(&PeerId(2)).unwrap().invulnerability = 0.0;
        assert_eq!(
            p.hit(&mut c, PeerId(1), PeerId(2), 100.0, false),
            (true, true)
        );
    }

    #[test]
    fn optional_bots_balance_solo_and_yield_to_joining_humans() {
        let mut p = Pvp {
            fill_bots: true,
            ..Default::default()
        };
        let mut c = Coop::default();
        assert!(p.register(PeerId(1), "solo".into()));
        p.refill_bots(&mut c);
        assert_eq!(p.counts(), [1, 1]);
        assert_eq!(p.fighters.values().filter(|f| f.is_bot).count(), 1);
        p.start(&mut c);
        assert!(p.register(PeerId(2), "human".into()));
        c.register(PeerId(2), "human".into(), 1);
        p.refill_bots(&mut c);
        assert_eq!(p.counts(), [1, 1]);
        assert!(p.fighters.values().all(|f| !f.is_bot));
        assert_eq!(c.players.len(), 2);
        let mut without = Pvp::default();
        without.register(PeerId(1), "solo".into());
        without.refill_bots(&mut c);
        assert_eq!(without.fighters.len(), 1);
    }
}
