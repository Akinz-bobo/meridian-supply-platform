output "arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "The part of the ARN that CloudWatch metrics use as the LoadBalancer dimension."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "Host name of the load balancer. Point the environment's domain at it."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Hosted zone of the load balancer, for an alias record."
  value       = aws_lb.this.zone_id
}

output "https_listener_arn" {
  description = "ARN of the TLS listener. A service adds its listener rule to it."
  value       = aws_lb_listener.https.arn
}
