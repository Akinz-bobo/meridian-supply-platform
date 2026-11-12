output "access_analyzer_arn" {
  description = "ARN of the access analyzer. Its findings list resources shared outside the account."
  value       = aws_accessanalyzer_analyzer.this.arn
}
