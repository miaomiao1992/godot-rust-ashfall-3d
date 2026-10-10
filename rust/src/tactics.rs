//! Readable deterministic attacks and distinct sector encounter pacing.
use std::f32::consts::TAU;

#[derive(Clone, Debug, PartialEq)]
pub struct AcidSpot {
    pub lateral: f32,
    pub forward: f32,
    pub delay: f32,
}

#[derive(Debug)]
pub struct AcidPattern {
    pub name: &'static str,
    pub hint: &'static str,
    pub radius: f32,
    pub warning: f32,
    pub active: f32,
    pub spots: Vec<AcidSpot>,
}

pub fn acid_pattern(stage: i32, step: i32, elite: bool) -> AcidPattern {
    let mut p = AcidPattern {
        name: "定点腐蚀",
        hint: "落点已锁定 · 离开琥珀色预警圈",
        radius: 2.2,
        warning: 1.6,
        active: 3.2,
        spots: Vec::new(),
    };
    if elite {
        p.radius = 1.9;
        p.active = 2.8;
        p.spots.push(AcidSpot {
            lateral: 0.0,
            forward: 0.0,
            delay: 0.0,
        });
    } else if stage == 2 {
        p.name = "十字喷发";
        p.hint = "固定十字 · 向四个对角空隙闪避";
        for (i, (x, z)) in [(0.0, 0.0), (-6.5, 0.0), (6.5, 0.0), (0.0, -6.5), (0.0, 6.5)]
            .iter()
            .enumerate()
        {
            p.spots.push(AcidSpot {
                lateral: *x,
                forward: *z,
                delay: i as f32 * 0.16,
            });
        }
    } else if step.rem_euclid(2) == 0 {
        p.name = "三连腐蚀";
        p.hint = "固定三连线 · 横向离开路径";
        for (i, z) in [-6.5, 0.0, 6.5].iter().enumerate() {
            p.spots.push(AcidSpot {
                lateral: 0.0,
                forward: *z,
                delay: i as f32 * 0.35,
            });
        }
    } else {
        p.name = "环形封锁";
        p.hint = "环形封锁 · 中央及圈间缺口安全";
        for i in 0..5 {
            let angle = i as f32 * TAU / 5.0;
            p.spots.push(AcidSpot {
                lateral: angle.sin() * 8.0,
                forward: angle.cos() * 8.0,
                delay: 0.0,
            });
        }
    }
    p
}

pub fn spawn_interval(stage: i32, wave: i32, cursor: i32) -> f32 {
    match stage {
        1 => {
            if cursor % 6 == 0 {
                2.6
            } else {
                0.18
            }
        }
        2 => {
            if cursor % 8 == 0 {
                2.0
            } else {
                0.16
            }
        }
        _ => (0.55 - wave as f32 * 0.035).max(0.25),
    }
}

pub fn gate_index(stage: i32, wave: i32, cursor: i32, count: i32) -> i32 {
    let group = match stage {
        1 => cursor / 6,
        2 => cursor / 8,
        _ => cursor,
    };
    // Laboratory gates rotate clockwise; dock bursts alternate non-adjacent piers.
    let gate = if stage == 1 {
        [0, 2, 1, 3][group.rem_euclid(4) as usize]
    } else {
        group + wave - 1
    };
    gate.rem_euclid(count.max(1))
}

pub fn objective_required(stage: i32, stage_wave: i32) -> i32 {
    if stage == 2 {
        stage_wave.clamp(1, 3)
    } else {
        0
    }
}

pub fn reactor_damage_factor(stage: i32, valves: i32) -> f32 {
    if stage == 2 && valves < 3 { 0.35 } else { 1.0 }
}

#[derive(Default)]
pub struct SectorGoals {
    mask: u8,
}

impl SectorGoals {
    pub fn activate(&mut self, index: i32) -> bool {
        if !(0..3).contains(&index) || self.mask & (1 << index) != 0 {
            return false;
        }
        self.mask |= 1 << index;
        true
    }
    pub fn count(&self) -> i32 {
        self.mask.count_ones() as i32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn patterns_are_repeatable_have_gaps_and_provide_dodge_time() {
        for stage in 0..3 {
            for step in 0..4 {
                let p = acid_pattern(stage, step, false);
                assert_eq!(p.spots, acid_pattern(stage, step, false).spots);
                assert!(p.warning >= 1.6 && p.spots.len() <= 5);
                for (i, a) in p.spots.iter().enumerate() {
                    for b in &p.spots[i + 1..] {
                        let distance = ((a.lateral - b.lateral).powi(2)
                            + (a.forward - b.forward).powi(2))
                        .sqrt();
                        assert!(
                            distance > p.radius * 2.0 + 1.0,
                            "escape gaps must remain open"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn elite_casts_only_one_short_lived_spot() {
        let p = acid_pattern(1, 99, true);
        assert_eq!(p.spots.len(), 1);
        assert!(p.active < 3.0);
    }

    #[test]
    fn pier_bursts_and_rotating_arena_gates_have_real_recovery_gaps() {
        assert_eq!(gate_index(1, 4, 0, 4), 0);
        assert_eq!(gate_index(1, 4, 6, 4), 2);
        assert_eq!(gate_index(1, 4, 12, 4), 1);
        assert!(spawn_interval(1, 4, 6) > spawn_interval(1, 4, 5) * 10.0);
        assert_ne!(gate_index(2, 7, 0, 4), gate_index(2, 7, 8, 4));
    }

    #[test]
    fn valves_are_unique_and_required_for_each_laboratory_wave() {
        let mut goals = SectorGoals::default();
        assert!(goals.activate(1));
        assert!(!goals.activate(1));
        assert!(!goals.activate(3));
        assert_eq!(goals.count(), 1);
        assert_eq!(objective_required(0, 3), 0);
        assert_eq!(objective_required(2, 2), 2);
        assert!(reactor_damage_factor(2, 2) < reactor_damage_factor(2, 3));
    }
}
