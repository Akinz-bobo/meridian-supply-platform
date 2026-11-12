# The application load balancer: the only thing in an environment that
# accepts traffic from outside the VPC.
#
# It listens on 443 with TLS and nothing else by default. A request that no
# rule matches is refused by the load balancer itself and never reaches a
# service. Services attach themselves with a target group and a listener
# rule of their own.

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = var.internal

  subnets         = var.subnet_ids
  security_groups = var.security_group_ids

  # A request with a malformed header is dropped here and not passed on for
  # a service to misread.
  drop_invalid_header_fields = true

  # Refuse requests that a front end and a back end could parse
  # differently, which is how request smuggling works.
  desync_mitigation_mode = "strictest"

  enable_deletion_protection = var.deletion_protection

  # Close idle connections before the services behind do, so the load
  # balancer never forwards on a connection the service has already closed.
  idle_timeout = var.idle_timeout_seconds

  enable_http2 = true

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.tls_policy
  certificate_arn   = var.certificate_arn

  # Nothing is served by default. A path with no rule gets this answer
  # from the load balancer, so a forgotten or mistyped route cannot fall
  # through to whichever service happens to be first.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = jsonencode({ error = "not found" })
      status_code  = "404"
    }
  }

  tags = var.tags
}

# Optional. Plain HTTP is never served: this only tells a client that
# asked on port 80 to come back on 443.
resource "aws_lb_listener" "http_redirect" {
  count = var.redirect_http ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}
