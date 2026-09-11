module "vpc" {
  source = "./modules/vpc"
  # No overrides needed — the module's own defaults already match the real
  # Phase 1 CIDR plan exactly.
}
