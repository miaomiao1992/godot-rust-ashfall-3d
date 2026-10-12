//! Engine-independent combat and campaign rules. Godot is the presentation layer.

#[derive(Clone, Copy, Debug)]
pub struct Weapon {
    pub name: &'static str,
    pub short: &'static str,
    pub sound: &'static str,
    pub level: i32,
    pub damage: f32,
    pub rate: f32,
    pub magazine: i32,
    pub reserve: i32,
    pub reload: f32,
    pub pellets: i32,
    pub spread: f32,
    pub recoil: f32,
    pub force: f32,
    pub automatic: bool,
}

pub const WEAPONS: [Weapon; 6] = [
    Weapon {
        name: "P-09 守夜者",
        short: "守夜者",
        sound: "pistol",
        level: 1,
        damage: 34.0,
        rate: 0.24,
        magazine: 15,
        reserve: 999,
        reload: 1.15,
        pellets: 1,
        spread: 0.008,
        recoil: 0.038,
        force: 2.5,
        automatic: false,
    },
    Weapon {
        name: "V-45 疾风",
        short: "疾风",
        sound: "smg",
        level: 2,
        damage: 24.0,
        rate: 0.078,
        magazine: 36,
        reserve: 240,
        reload: 1.5,
        pellets: 1,
        spread: 0.020,
        recoil: 0.022,
        force: 1.7,
        automatic: true,
    },
    Weapon {
        name: "SG-8 破门者",
        short: "破门者",
        sound: "shotgun",
        level: 3,
        damage: 22.0,
        rate: 0.82,
        magazine: 8,
        reserve: 56,
        reload: 2.05,
        pellets: 10,
        spread: 0.07,
        recoil: 0.095,
        force: 4.0,
        automatic: false,
    },
    Weapon {
        name: "AR-37 灰烬",
        short: "灰烬",
        sound: "rifle",
        level: 5,
        damage: 49.0,
        rate: 0.125,
        magazine: 30,
        reserve: 180,
        reload: 1.75,
        pellets: 1,
        spread: 0.014,
        recoil: 0.035,
        force: 3.2,
        automatic: true,
    },
    Weapon {
        name: "RX-1 审判",
        short: "审判",
        sound: "coil",
        level: 7,
        damage: 210.0,
        rate: 1.05,
        magazine: 6,
        reserve: 36,
        reload: 2.35,
        pellets: 1,
        spread: 0.001,
        recoil: 0.07,
        force: 10.0,
        automatic: false,
    },
    Weapon {
        name: "SR-96 远望",
        short: "远望",
        sound: "sniper",
        level: 8,
        damage: 125.0,
        rate: 1.45,
        magazine: 5,
        reserve: 30,
        reload: 2.8,
        pellets: 1,
        spread: 0.025,
        recoil: 0.085,
        force: 8.0,
        automatic: false,
    },
];

/// Limits in metres along the ray, so oblique hits pay for more material.
pub fn penetration_limit(weapon: usize, surface: &str) -> f32 {
    let limits = match weapon {
        0 => [0.0, 0.0, 0.18],
        1 => [0.0, 0.0, 0.25],
        3 => [0.25, 0.10, 0.65],
        4 => [1.0, 0.50, 2.2],
        5 => [0.55, 0.30, 1.2],
        _ => [0.0; 3],
    };
    limits[match surface {
        "metal" => 1,
        "wood" | "plastic" => 2,
        _ => 0,
    }]
}

pub fn penetration_factor(weapon: usize, surface: &str, thickness: f32) -> f32 {
    let limit = penetration_limit(weapon, surface);
    if !thickness.is_finite() || thickness <= 0.0 || limit == 0.0 || thickness > limit {
        return 0.0;
    }
    (1.0 - thickness / limit * 0.8).clamp(0.2, 0.95)
}

pub fn blast_cover_limit(surface: &str) -> f32 {
    match surface {
        "wood" | "plastic" => 2.5,
        "metal" => 0.5,
        _ => 1.2,
    }
}

pub fn blast_cover_factor(surface: &str, thickness: f32) -> f32 {
    if !thickness.is_finite() || thickness <= 0.0 || thickness > blast_cover_limit(surface) {
        return 0.0;
    }
    let resistance = match surface {
        "wood" | "plastic" => 1.2,
        "metal" => 6.0,
        _ => 4.5,
    };
    (-thickness * resistance).exp()
}

#[derive(Clone, Copy, Debug)]
pub struct Monster {
    pub name: &'static str,
    pub tier: &'static str,
    pub hp: f32,
    pub speed: f32,
    pub damage: f32,
    pub scale: f32,
    pub xp: i32,
    pub body_armor: f32,
}

pub const MONSTERS: [Monster; 6] = [
    Monster {
        name: "感染者",
        tier: "小怪",
        hp: 75.0,
        speed: 2.1,
        damage: 10.0,
        scale: 1.0,
        xp: 18,
        body_armor: 1.0,
    },
    Monster {
        name: "疾行者",
        tier: "小怪",
        hp: 50.0,
        speed: 4.4,
        damage: 8.0,
        scale: 0.88,
        xp: 22,
        body_armor: 1.0,
    },
    Monster {
        name: "屠戮者",
        tier: "精英",
        hp: 380.0,
        speed: 1.55,
        damage: 26.0,
        scale: 1.5,
        xp: 80,
        body_armor: 1.0,
    },
    Monster {
        name: "装甲感染者",
        tier: "精英",
        hp: 160.0,
        speed: 2.4,
        damage: 16.0,
        scale: 1.1,
        xp: 34,
        body_armor: 0.55,
    },
    Monster {
        name: "疫潮母体",
        tier: "BOSS",
        hp: 1800.0,
        speed: 1.7,
        damage: 38.0,
        scale: 2.6,
        xp: 280,
        body_armor: 0.8,
    },
    Monster {
        name: "腐蚀者",
        tier: "精英",
        hp: 125.0,
        speed: 1.75,
        damage: 12.0,
        scale: 1.06,
        xp: 42,
        body_armor: 1.0,
    },
];

pub const STAGES: [&str; 3] = ["断桥高架", "沉没船坞", "熔心实验场"];
pub const BOSSES: [&str; 3] = ["断街暴君", "溺潮巨骸", "疫潮母体"];

pub fn monster(kind: i32, wave: i32) -> Monster {
    let mut m = MONSTERS[kind.clamp(0, 5) as usize];
    m.hp *= 1.0 + (wave - 1).max(0) as f32 * 0.085;
    m.speed *= 1.0 + (wave as f32 * 0.022).min(0.35);
    m
}

pub fn hit_damage(kind: i32, base: f32, head: bool) -> f32 {
    base.max(0.0)
        * if head {
            2.5
        } else {
            MONSTERS[kind.clamp(0, 5) as usize].body_armor
        }
}

pub fn spawn_kind(wave: i32, roll: f32) -> i32 {
    if wave >= 3 && roll < 0.07 {
        2
    } else if wave >= 4 && roll < 0.17 {
        3
    } else if wave >= 2 && roll < 0.27 {
        5
    } else if roll < 0.45 {
        1
    } else {
        0
    }
}

pub fn boss_action(stage: i32, distance: f32, step: i32, enraged: bool) -> &'static str {
    if distance < 8.5 {
        return "smash";
    }
    match (stage, step.rem_euclid(if enraged { 3 } else { 4 })) {
        (1, 0 | 2) => "acid",
        (_, 1) => "summon",
        (2, 2) => "acid",
        _ => "charge",
    }
}

#[derive(Debug)]
pub struct Run {
    pub wave: i32,
    pub xp: i32,
    pub xp_needed: i32,
    pub level: i32,
    pub kills: i32,
    pub headshots: i32,
    pub damage_multiplier: f32,
    pub max_hp: f32,
    pub resistance: f32,
    pub reload_multiplier: f32,
    pub speed_bonus: f32,
}

impl Default for Run {
    fn default() -> Self {
        Self {
            wave: 0,
            xp: 0,
            xp_needed: 80,
            level: 1,
            kills: 0,
            headshots: 0,
            damage_multiplier: 1.0,
            max_hp: 100.0,
            resistance: 0.0,
            reload_multiplier: 1.0,
            speed_bonus: 0.0,
        }
    }
}

impl Run {
    pub fn stage(&self) -> i32 {
        ((self.wave - 1).max(0) / 3).min(2)
    }
    pub fn stage_wave(&self) -> i32 {
        (self.wave - 1).max(0) % 3 + 1
    }
    pub fn advance_wave(&mut self) {
        self.wave = (self.wave + 1).min(9);
    }
    pub fn budget(&self) -> i32 {
        22 + self.wave * 12
    }
    pub fn reward(&mut self, kind: i32, head: bool) -> (i32, i32) {
        let reward = MONSTERS[kind.clamp(0, 5) as usize].xp + if head { 7 } else { 0 };
        self.kills += 1;
        self.headshots += i32::from(head);
        self.xp += reward;
        let mut levels = 0;
        while self.xp >= self.xp_needed {
            self.xp -= self.xp_needed;
            self.level += 1;
            self.xp_needed = 80 + (self.level - 1) * 50;
            levels += 1;
        }
        (reward, levels)
    }
    pub fn upgrade(&mut self, index: i32) -> f32 {
        match index {
            0 => {
                self.damage_multiplier += 0.18;
                0.0
            }
            1 => {
                self.max_hp += 20.0;
                self.resistance = (self.resistance + 0.04).min(0.4);
                45.0
            }
            2 => {
                self.reload_multiplier = (self.reload_multiplier * 0.88).max(0.4);
                self.speed_bonus += 0.25;
                18.0
            }
            _ => 0.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn campaign_has_three_stages_each_with_a_boss_wave() {
        let mut run = Run::default();
        for wave in 1..=9 {
            run.advance_wave();
            assert_eq!(run.wave, wave);
            assert_eq!(run.stage(), (wave - 1) / 3);
            assert_eq!(run.stage_wave() == 3, wave % 3 == 0);
        }
        run.advance_wave();
        assert_eq!(run.wave, 9);
    }

    #[test]
    fn boss_reward_can_cross_multiple_level_boundaries_without_losing_xp() {
        let mut run = Run::default();
        let (reward, levels) = run.reward(4, true);
        assert_eq!(reward, 287);
        assert_eq!(levels, 2);
        assert_eq!((run.level, run.xp, run.xp_needed), (3, 77, 180));
        assert_eq!(run.headshots, 1);
    }

    #[test]
    fn armor_is_countered_by_headshots_and_boss_is_durable() {
        assert!(hit_damage(3, 40.0, true) > hit_damage(3, 40.0, false) * 4.0);
        assert!(monster(4, 9).hp > monster(2, 9).hp * 4.0);
    }

    #[test]
    fn upgrade_caps_keep_damage_and_reload_valid() {
        let mut run = Run::default();
        for _ in 0..100 {
            run.upgrade(1);
            run.upgrade(2);
        }
        assert_eq!(run.resistance, 0.4);
        assert_eq!(run.reload_multiplier, 0.4);
        assert!(WEAPONS.windows(2).all(|w| w[0].level < w[1].level));
    }

    #[test]
    fn monster_pool_and_boss_actions_are_different() {
        assert_eq!(spawn_kind(1, 0.1), 1);
        assert_eq!(spawn_kind(4, 0.1), 3);
        assert_eq!(spawn_kind(4, 0.2), 5);
        assert_eq!(boss_action(0, 20.0, 0, false), "charge");
        assert_eq!(boss_action(1, 20.0, 0, false), "acid");
        assert_eq!(boss_action(2, 4.0, 0, true), "smash");
    }

    #[test]
    fn penetration_is_material_weapon_and_thickness_dependent() {
        assert_eq!(penetration_factor(0, "concrete", 0.1), 0.0);
        assert_eq!(penetration_factor(2, "wood", 0.1), 0.0);
        assert!(penetration_factor(3, "wood", 0.2) > 0.5);
        assert_eq!(penetration_factor(3, "metal", 0.2), 0.0);
        assert!(penetration_factor(5, "metal", 0.2) > 0.0);
        assert!(penetration_factor(4, "concrete", 0.7) > 0.0);
        for invalid in [f32::NAN, f32::INFINITY, -1.0, 0.0] {
            assert_eq!(penetration_factor(5, "wood", invalid), 0.0);
            assert_eq!(blast_cover_factor("wood", invalid), 0.0);
        }
    }

    #[test]
    fn blast_cover_compounds_and_heavy_walls_stop_transmission() {
        let thin = blast_cover_factor("wood", 0.18);
        assert!(thin > 0.5 && thin < 1.0);
        assert!(thin * thin < thin);
        assert!(blast_cover_factor("concrete", 1.0) < 0.03);
        assert_eq!(blast_cover_factor("concrete", 1.5), 0.0);
    }
}
