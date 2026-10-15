package main

import "testing"

func TestShouldHold(t *testing.T) {
	if shouldHold(true, true, 20, false, true, 100, true) {
		t.Fatal("pause wins")
	}
	if shouldHold(false, false, 20, true, true, 18, true) {
		t.Fatal("floor releases")
	}
	if !shouldHold(false, false, 20, false, true, 100, true) {
		t.Fatal("running app holds")
	}
	if !shouldHold(false, true, 20, false, true, 100, false) {
		t.Fatal("manual holds")
	}
	if shouldHold(false, false, 20, false, true, 100, false) {
		t.Fatal("idle can sleep")
	}
}
