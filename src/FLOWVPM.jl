"""
# DESCRIPTION
    Implementation of the three-dimensional viscous Vortex Particle Method
    written in Julia 1.4.2.

# AUTHORSHIP
  * Author    : Eduardo J. Alvarez
  * Email     : Edo.AlvarezR@gmail.com
  * Created   : 2019
  * Copyright : Eduardo J Alvarez. All rights reserved. No licensing, use, or
        modification of this code is allowed without written consent.

# TODO
* [ ] Implement reformulation on Runge-Kutta integration.
* [ ] Reduce memory of ParticleTube: l0, l, and M.
* [ ] RBF testing: Point and ring test cases.
* [ ] Print and save setting at beginning of simulation.
* [ ] Feature of probing the fluid domain.
* [ ] Optimize creating of hdf5s to speed up simulations.
"""
module FLOWVPM

# ------------ GENERIC MODULES -------------------------------------------------
import HDF5
import SpecialFunctions
import Dates

# ------------ FLOW CODES ------------------------------------------------------
import FLOWExaFMM
const fmm = FLOWExaFMM

# ------------ GLOBAL VARIABLES ------------------------------------------------
const module_path = splitdir(@__FILE__)[1]      # Path to this module

# Determine the floating point precision of ExaFMM
const exafmm_single_precision = fmm.getPrecision()
const RealFMM = exafmm_single_precision ? Float32 : Float64

# ------------ HEADERS ---------------------------------------------------------
for header_name in ["kernel", "fmm", "viscous", "formulation",
                    "particle", "particlefield",
                    "UJ", "timeintegration",
                    "utils"]
    include(joinpath( module_path, "FLOWVPM_"*header_name*".jl" ))
end

# Available VPM formulations
const formulation_classic = ClassicVPM{RealFMM}()
const formulation_tube_classic = ReformulatedVPM{RealFMM}(0, 0)
const formulation_tube_continuity = ReformulatedVPM{RealFMM}(1/2, 0)
const formulation_tube_momentum = ReformulatedVPM{RealFMM}(1/4, 1/4)
const formulation_sphere_momentum = ReformulatedVPM{RealFMM}(0, 1/5)
const formulation_default = formulation_sphere_momentum
# const formulation_default = formulation_classic


# Available Kernels
const kernel_singular = Kernel(zeta_sing, g_sing, dgdr_sing, g_dgdr_sing, 1, 1)
const kernel_gaussian = Kernel(zeta_gaus, g_gaus, dgdr_gaus, g_dgdr_gaus, -1, 1)
const kernel_gaussianerf = Kernel(zeta_gauserf, g_gauserf, dgdr_gauserf, g_dgdr_gauserf, 5, 1)
const kernel_winckelmans = Kernel(zeta_wnklmns, g_wnklmns, dgdr_wnklmns, g_dgdr_wnklmns, 3, 1)
const kernel_default = kernel_gaussianerf

# Kernel aliases
const singular = kernel_singular
const gaussian = kernel_gaussian
const gaussianerf = kernel_gaussianerf
const winckelmans = kernel_winckelmans

# Compatibility between kernels and viscous schemes
const kernel_compatibility = Dict( # Viscous scheme => kernels
        Inviscid.body.name      => [singular, gaussian, gaussianerf, winckelmans,
                                        kernel_singular, kernel_gaussian,
                                        kernel_gaussianerf, kernel_winckelmans],
        CoreSpreading.body.name => [gaussianerf, kernel_gaussianerf],
)

end # END OF MODULE
