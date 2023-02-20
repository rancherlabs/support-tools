package planner

import "context"

// NOTE: originally based on this https://gianarb.it/blog/reactive-plan-golang-example

type Plan interface {
	Name() string
	Create(ctx context.Context) ([]Procedure, error)
}

type Procedure interface {
	Name() string
	Do(ctx context.Context) ([]Procedure, error)
}
