use crate::error::Result;
use crate::planner::{effect_to_json, Effect};

pub fn print(effects: &[Effect], json: bool) -> Result<()> {
    if json {
        let value = effects.iter().map(effect_to_json).collect::<Vec<_>>();
        println!("{}", serde_json::to_string_pretty(&value)?);
    } else if effects.is_empty() {
        println!("(empty plan)");
    } else {
        for effect in effects {
            println!("{effect:?}");
        }
    }
    Ok(())
}
