package planner

import (
	"context"
	"fmt"
	"time"

	"go.uber.org/zap"
)

type Manager interface {
	Execute(ctx context.Context, p Plan) (int, error)
}

func NewManager(logger *zap.SugaredLogger) Manager {
	return &managerImpl{
		logger: logger,
	}
}

type managerImpl struct {
	logger *zap.SugaredLogger
}

func (m *managerImpl) Execute(ctx context.Context, plan Plan) (int, error) {
	logger := m.logger.With("plan_name", plan.Name())

	planStart := time.Now().UTC()

	logger.Info("started executing plan")

	numExecutedSteps, err := m.executePlan(ctx, plan, logger)
	if err != nil {
		logger.With("execution_time", time.Since(planStart), "num_steps", numExecutedSteps).Errorw("failed executing plan", "error", err)
	}

	logger.With("execution_time", time.Since(planStart), "num_steps", numExecutedSteps).Info("finished executing plan")

	return numExecutedSteps, nil
}

func (m *managerImpl) executePlan(ctx context.Context, plan Plan, logger *zap.SugaredLogger) (int, error) {
	numExecutedSteps := 0

	for {
		steps, err := plan.Create(ctx)
		if err != nil {
			return numExecutedSteps, fmt.Errorf("creating plan for %s: %w", plan.Name(), err)
		}

		if len(steps) == 0 {
			logger.Debug("no steps to execute")

			return numExecutedSteps, nil
		}

		executed, err := m.react(ctx, steps, logger)
		numExecutedSteps += executed

		if err != nil {
			return numExecutedSteps, fmt.Errorf("executing steps: %w", err)
		}
	}
}

func (m *managerImpl) react(ctx context.Context, steps []Procedure, logger *zap.SugaredLogger) (int, error) {
	var children []Procedure

	numExecutedSteps := 0

	for _, step := range steps {
		var err error
		stepLogger := logger.With("step_name", step.Name())
		select {
		case <-ctx.Done():
			stepLogger.Info("step not executed as context is done")
			return numExecutedSteps, ctx.Err()
		default:
			stepLogger.Debug("executing step")
			numExecutedSteps++

			children, err = step.Do(ctx)
			if err != nil {
				return numExecutedSteps, fmt.Errorf("executing step %s: %w", step.Name(), err)
			}
		}

		if len(children) > 0 {
			executed, err := m.react(ctx, children, logger)
			numExecutedSteps += executed

			if err != nil {
				return numExecutedSteps, err
			}
		}
	}

	return numExecutedSteps, nil
}
