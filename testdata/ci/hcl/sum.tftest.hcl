variables {
  a = 2
  b = 3
}

run "sum" {
  command = plan

  assert {
    condition     = output.sum == 5
    error_message = "sum should be 5"
  }
}
