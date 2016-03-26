#!/usr/bin/env python
import pylab


dt = 0.01

U = 1.0
V = 1.0

us = []
vs = []

t = 0.0

while t < 1000.0:
    # van der Pol oscillator
    # mu = 0.1
    # dU_dt = V
    # dV_dt = mu*(1-U*U)*V - U


    dU_dt = - 2.0 * U * V + 1.0 * V
    dV_dt =   1.0 * U * V - 0.5 * V

    U += dt * dU_dt
    V += dt * dV_dt
    us.append(U)
    vs.append(V)
    t += dt

pylab.rcParams['figure.figsize'] = (10.0, 10.0)
pylab.clf()
pylab.plot(us,vs)
pylab.savefig("lv.png")
