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
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for AshfallCore {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            run: rules::Run::default(),
            crowd: Vec::new(),
            goals: tactics::SectorGoals::default(),
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
        d.set("budget", self.run.budget());
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
        let m = rules::monster(kind, wave);
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
