output "bus_name" {
  description = "Name of the environment's event bus."
  value       = module.event_bus.bus_name
}

output "publishers" {
  description = "Services that have a publish policy for the bus."
  value       = keys(module.event_bus.publish_policy_json)
}
