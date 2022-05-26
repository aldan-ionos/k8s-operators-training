package controllers_test

import (
	"k8s-operators-training/controllers"
	"testing"
)

func TestInformerExample(t *testing.T) {
	if err := controllers.InformerExample(); err != nil {
		t.Errorf("informer error: %s", err.Error())
	}
}
