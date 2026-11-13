variable "a" {
  type = number
}

variable "b" {
  type = number
}

output "sum" {
  value = var.a + var.b
}
