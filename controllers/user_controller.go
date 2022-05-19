/*
Copyright 2022.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controllers

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/api/errors"

	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	generalv1 "k8s-operators-training/api/v1"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var (
	requeue = ctrl.Result{Requeue: true}
	done    = ctrl.Result{}
)

// UserReconciler reconciles a User object
type UserReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

//+kubebuilder:rbac:groups=general.k8s-operators-training,resources=users,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=general.k8s-operators-training,resources=users/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=general.k8s-operators-training,resources=users/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the User object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.11.0/pkg/reconcile
func (r *UserReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	key := types.NamespacedName{
		Name:      req.Name,
		Namespace: req.Namespace,
	}

	// Get User CRD
	user := &generalv1.User{}
	if err := r.Client.Get(ctx, key, user); err != nil {
		if errors.IsNotFound(err) {
			return done, nil
		}
		return requeue, err
	}

	if err := r.Client.Get(ctx, key, &corev1.Secret{}); err != nil {
		if errors.IsNotFound(err) {
			// Create secret based on user CRD
			if err := r.createSecret(ctx, user); err != nil {
				return requeue, err
			}
		} else {
			return requeue, err
		}
	} else {
		// Update secret based on user CRD
		if err := r.updateSecret(ctx, user); err != nil {
			return requeue, err
		}
	}

	// Delete user CRD
	if err := r.Delete(ctx, user); err != nil && !errors.IsNotFound(err) {
		return requeue, err
	}

	return done, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *UserReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&generalv1.User{}).
		Complete(r)
}

func (r *UserReconciler) createSecret(ctx context.Context, user *generalv1.User) error {
	return r.Client.Create(ctx, &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      user.Name,
			Namespace: user.Namespace,
		},
		StringData: map[string]string{
			"id":       fmt.Sprintf("%d", user.Spec.Id),
			"username": user.Spec.Username,
			"password": user.Spec.Password,
		},
	})
}

func (r *UserReconciler) updateSecret(ctx context.Context, user *generalv1.User) error {
	return r.Client.Update(ctx, &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name:      user.Name,
			Namespace: user.Namespace,
		},
		StringData: map[string]string{
			"id":       fmt.Sprintf("%d", user.Spec.Id),
			"username": user.Spec.Username,
			"password": user.Spec.Password,
		},
	})
}
