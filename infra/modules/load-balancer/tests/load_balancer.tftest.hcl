# Plan-only tests against a mocked provider. No AWS account or emulator is
# needed.

mock_provider "aws" {}

variables {
  name               = "meridian-prod-compute"
  subnet_ids         = ["subnet-public-a", "subnet-public-b", "subnet-public-c"]
  security_group_ids = ["sg-lb"]
  certificate_arn    = "arn:aws:acm:eu-west-1:333333333333:certificate/11111111-2222-3333-4444-555555555555"
  tags = {
    Project = "meridian"
  }
}

run "serves_tls_only_by_default" {
  command = plan

  assert {
    condition     = aws_lb_listener.https.port == 443 && aws_lb_listener.https.protocol == "HTTPS"
    error_message = "The listener is HTTPS on 443."
  }

  assert {
    condition     = length(aws_lb_listener.http_redirect) == 0
    error_message = "There is no port 80 listener unless asked for."
  }
}

run "accepts_modern_tls_only" {
  command = plan

  assert {
    condition     = aws_lb_listener.https.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "The default policy accepts TLS 1.3 and 1.2 only."
  }
}

run "refuses_what_no_rule_matches" {
  command = plan

  assert {
    condition     = aws_lb_listener.https.default_action[0].type == "fixed-response" && aws_lb_listener.https.default_action[0].fixed_response[0].status_code == "404"
    error_message = "The default action must be a fixed refusal, not a forward to a service."
  }
}

run "drops_malformed_requests" {
  command = plan

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields
    error_message = "Invalid header fields must be dropped."
  }

  assert {
    condition     = aws_lb.this.desync_mitigation_mode == "strictest"
    error_message = "Requests that could be parsed two ways must be refused."
  }
}

run "cannot_be_deleted_by_default" {
  command = plan

  assert {
    condition     = aws_lb.this.enable_deletion_protection
    error_message = "Deletion protection must default to on."
  }
}

run "port_80_only_redirects" {
  command = plan

  variables {
    redirect_http = true
  }

  assert {
    condition     = aws_lb_listener.http_redirect[0].default_action[0].type == "redirect" && aws_lb_listener.http_redirect[0].default_action[0].redirect[0].protocol == "HTTPS" && aws_lb_listener.http_redirect[0].default_action[0].redirect[0].status_code == "HTTP_301"
    error_message = "A port 80 listener may only redirect to HTTPS, permanently."
  }
}

run "can_be_internal" {
  command = plan

  variables {
    internal = true
  }

  assert {
    condition     = aws_lb.this.internal
    error_message = "internal must reach the load balancer."
  }
}

run "rejects_an_old_tls_policy" {
  command = plan

  variables {
    tls_policy = "ELBSecurityPolicy-2016-08"
  }

  expect_failures = [var.tls_policy]
}

run "rejects_a_listener_without_a_certificate" {
  command = plan

  variables {
    certificate_arn = ""
  }

  expect_failures = [var.certificate_arn]
}

run "rejects_a_single_zone" {
  command = plan

  variables {
    subnet_ids = ["subnet-public-a"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_a_name_longer_than_the_service_allows" {
  command = plan

  variables {
    name = "meridian-production-compute-load-balancer"
  }

  expect_failures = [var.name]
}
