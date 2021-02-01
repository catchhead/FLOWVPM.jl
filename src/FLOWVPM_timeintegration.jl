#=##############################################################################
# DESCRIPTION
    Time integration schemes.

# AUTHORSHIP
  * Author    : Eduardo J Alvarez
  * Email     : Edo.AlvarezR@gmail.com
  * Created   : Aug 2020
  * Copyright : Eduardo J Alvarez. All rights reserved.
=###############################################################################

"""
Steps the field forward in time by dt in a first-order Euler integration scheme.
"""
function euler(pfield::ParticleField{R, <:ClassicVPM, V},
                                dt::Real; relax::Bool=false) where {R, V}

    # Reset U and J to zero
    _reset_particles(pfield)

    # Calculate interactions between particles: U and J
    pfield.UJ(pfield)

    # Calculate subgrid-scale contributions
    _reset_particles_sgs(pfield)
    pfield.sgsmodel(pfield)

    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    # Update the particle field: convection and stretching
    for p in iterator(pfield)

        # Update position
        p.X[1] += dt*(p.U[1] + Uinf[1])
        p.X[2] += dt*(p.U[2] + Uinf[2])
        p.X[3] += dt*(p.U[3] + Uinf[3])

        # Update vectorial circulation
        ## Vortex stretching contributions
        if pfield.transposed
            # Transposed scheme (Γ⋅∇')U
            p.Gamma[1] += dt*(p.J[1,1]*p.Gamma[1]+p.J[2,1]*p.Gamma[2]+p.J[3,1]*p.Gamma[3])
            p.Gamma[2] += dt*(p.J[1,2]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[3,2]*p.Gamma[3])
            p.Gamma[3] += dt*(p.J[1,3]*p.Gamma[1]+p.J[2,3]*p.Gamma[2]+p.J[3,3]*p.Gamma[3])
        else
            # Classic scheme (Γ⋅∇)U
            p.Gamma[1] += dt*(p.J[1,1]*p.Gamma[1]+p.J[1,2]*p.Gamma[2]+p.J[1,3]*p.Gamma[3])
            p.Gamma[2] += dt*(p.J[2,1]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[2,3]*p.Gamma[3])
            p.Gamma[3] += dt*(p.J[3,1]*p.Gamma[1]+p.J[3,2]*p.Gamma[2]+p.J[3,3]*p.Gamma[3])
        end

        ## Subgrid-scale contributions
        p.Gamma[1] += dt*(getproperty(p, _SGS)[1])
        p.Gamma[2] += dt*(getproperty(p, _SGS)[2])
        p.Gamma[3] += dt*(getproperty(p, _SGS)[3])


        # Relaxation: Align vectorial circulation to local vorticity
        if relax
            pfield.relaxation(pfield.rlxf, p)
        end

    end

    # Update the particle field: viscous diffusion
    viscousdiffusion(pfield, dt)

    return nothing
end









"""
Steps the field forward in time by dt in a first-order Euler integration scheme
using the VPM reformulation. See notebook 20210104.
"""
function euler(pfield::ParticleField{R, <:ReformulatedVPM{R2}, V},
                              dt::Real; relax::Bool=false ) where {R, V, R2}

    # Reset U and J to zero
    _reset_particles(pfield)

    # Calculate interactions between particles: U and J
    pfield.UJ(pfield)

    # Calculate subgrid-scale contributions
    _reset_particles_sgs(pfield)
    pfield.sgsmodel(pfield)

    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    MM::Array{<:Real, 1} = pfield.M
    f::R2, g::R2 = pfield.formulation.f, pfield.formulation.g

    # Update the particle field: convection and stretching
    for p in iterator(pfield)

        # Update position
        p.X[1] += dt*(p.U[1] + Uinf[1])
        p.X[2] += dt*(p.U[2] + Uinf[2])
        p.X[3] += dt*(p.U[3] + Uinf[3])

        # Store stretching S under MM[1:3]
        if pfield.transposed
            # Transposed scheme S = (Γ⋅∇')U
            MM[1] = (p.J[1,1]*p.Gamma[1]+p.J[2,1]*p.Gamma[2]+p.J[3,1]*p.Gamma[3])
            MM[2] = (p.J[1,2]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[3,2]*p.Gamma[3])
            MM[3] = (p.J[1,3]*p.Gamma[1]+p.J[2,3]*p.Gamma[2]+p.J[3,3]*p.Gamma[3])
        else
            # Classic scheme S = (Γ⋅∇)U
            MM[1] = (p.J[1,1]*p.Gamma[1]+p.J[1,2]*p.Gamma[2]+p.J[1,3]*p.Gamma[3])
            MM[2] = (p.J[2,1]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[2,3]*p.Gamma[3])
            MM[3] = (p.J[3,1]*p.Gamma[1]+p.J[3,2]*p.Gamma[2]+p.J[3,3]*p.Gamma[3])
        end

        # Store Z under MM[4] with Z = [ (f+g)/(1+3f) * S⋅Γ + f/(1+3f) * M3⋅Γ ] / mag(Γ)^2
        MM[4] = (f+g)/(1+3*f) * (MM[1]*p.Gamma[1] + MM[2]*p.Gamma[2] + MM[3]*p.Gamma[3])
        MM[4] += f/(1+3*f) * (getproperty(p, _SGS)[1]*p.Gamma[1]
                                + getproperty(p, _SGS)[2]*p.Gamma[2]
                                + getproperty(p, _SGS)[3]*p.Gamma[3])
        MM[4] /= p.Gamma[1]^2 + p.Gamma[2]^2 + p.Gamma[3]^2

        # Update vectorial circulation ΔΓ = Δt*(S - 3ZΓ + M3)
        p.Gamma[1] += dt * (MM[1] - 3*MM[4]*p.Gamma[1] + getproperty(p, _SGS)[1])
        p.Gamma[2] += dt * (MM[2] - 3*MM[4]*p.Gamma[2] + getproperty(p, _SGS)[2])
        p.Gamma[3] += dt * (MM[3] - 3*MM[4]*p.Gamma[3] + getproperty(p, _SGS)[3])

        # Update cross-sectional area of the tube σ = -Δt*σ*Z
        p.sigma[1] -= dt * ( p.sigma[1] * MM[4] )

        # Relaxation: Alig vectorial circulation to local vorticity
        if relax
            pfield.relaxation(pfield.rlxf, p)
        end

    end

    # Update the particle field: viscous diffusion
    viscousdiffusion(pfield, dt)

    return nothing
end












"""
Steps the field forward in time by dt in a third-order low-storage Runge-Kutta
integration scheme. See Notebook entry 20180105.
"""
function rungekutta3(pfield::ParticleField{R, <:ClassicVPM, V},
                            dt::Real; relax::Bool=false) where {R, V}

    # Storage terms: qU <=> p.M[:, 1], qstr <=> p.M[:, 2], qsmg2 <=> p.M[1, 3]

    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    # Reset storage memory to zero
    for p in iterator(pfield); p.M .= zero(R); end;

    # Runge-Kutta inner steps
    for (a,b) in (R.((0, 1/3)), R.((-5/9, 15/16)), R.((-153/128, 8/15)))

        # Reset U and J from previous step
        _reset_particles(pfield)

        # Calculate interactions between particles: U and J
        pfield.UJ(pfield)

        # Calculate subgrid-scale contributions
        _reset_particles_sgs(pfield)
        pfield.sgsmodel(pfield)

        # Update the particle field: convection and stretching
        for p in iterator(pfield)

            # Low-storage RK step
            ## Velocity
            p.M[1, 1] = a*p.M[1, 1] + dt*(p.U[1] + Uinf[1])
            p.M[2, 1] = a*p.M[2, 1] + dt*(p.U[2] + Uinf[2])
            p.M[3, 1] = a*p.M[3, 1] + dt*(p.U[3] + Uinf[3])

            # Update position
            p.X[1] += b*p.M[1, 1]
            p.X[2] += b*p.M[2, 1]
            p.X[3] += b*p.M[3, 1]

            ## Stretching + SGS contributions
            if pfield.transposed
                # Transposed scheme (Γ⋅∇')U
                p.M[1, 2] = a*p.M[1, 2] + dt*(p.J[1,1]*p.Gamma[1]+p.J[2,1]*p.Gamma[2]+p.J[3,1]*p.Gamma[3] + getproperty(p, _SGS)[1])
                p.M[2, 2] = a*p.M[2, 2] + dt*(p.J[1,2]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[3,2]*p.Gamma[3] + getproperty(p, _SGS)[2])
                p.M[3, 2] = a*p.M[3, 2] + dt*(p.J[1,3]*p.Gamma[1]+p.J[2,3]*p.Gamma[2]+p.J[3,3]*p.Gamma[3] + getproperty(p, _SGS)[3])
            else
                # Classic scheme (Γ⋅∇)U
                p.M[1, 2] = a*p.M[1, 2] + dt*(p.J[1,1]*p.Gamma[1]+p.J[1,2]*p.Gamma[2]+p.J[1,3]*p.Gamma[3] + getproperty(p, _SGS)[1])
                p.M[2, 2] = a*p.M[2, 2] + dt*(p.J[2,1]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[2,3]*p.Gamma[3] + getproperty(p, _SGS)[2])
                p.M[3, 2] = a*p.M[3, 2] + dt*(p.J[3,1]*p.Gamma[1]+p.J[3,2]*p.Gamma[2]+p.J[3,3]*p.Gamma[3] + getproperty(p, _SGS)[3])
            end

            # Update vectorial circulation
            p.Gamma[1] += b*p.M[1, 2]
            p.Gamma[2] += b*p.M[2, 2]
            p.Gamma[3] += b*p.M[3, 2]

        end

        # Update the particle field: viscous diffusion
        viscousdiffusion(pfield, dt; aux1=a, aux2=b)

    end


    # Relaxation: Align vectorial circulation to local vorticity
    if relax

        # Resets U and J from previous step
        _reset_particles(pfield)

        # Calculates interactions between particles: U and J
        # NOTE: Technically we have to calculate J at the final location,
        #       but in MyVPM I just used the J calculated in the last RK step
        #       and it worked just fine. So maybe I perhaps I can save computation
        #       by not calculating UJ again.
        pfield.UJ(pfield)

        for p in iterator(pfield)
            # Align particle strength
            pfield.relaxation(pfield.rlxf, p)
        end
    end

    return nothing
end












"""
Steps the field forward in time by dt in a third-order low-storage Runge-Kutta
integration scheme using the VPM reformulation. See Notebook entry 20180105
(RK integration) and notebook 20210104 (reformulation).
"""
function rungekutta3(pfield::ParticleField{R, <:ReformulatedVPM{R2}, V},
                     dt::Real; relax::Bool=false ) where {R, V, R2}

    # Storage terms: qU <=> p.M[:, 1], qstr <=> p.M[:, 2], qsmg2 <=> p.M[1, 3],
    #                      qsmg <=> p.M[2, 3], Z <=> MM[4], S <=> MM[1:3]

    # Calculate freestream
    Uinf::Array{<:Real, 1} = pfield.Uinf(pfield.t)

    MM::Array{<:Real, 1} = pfield.M
    f::R2, g::R2 = pfield.formulation.f, pfield.formulation.g

    # Reset storage memory to zero
    for p in iterator(pfield); p.M .= zero(R); end;

    # Runge-Kutta inner steps
    for (a,b) in (R.((0, 1/3)), R.((-5/9, 15/16)), R.((-153/128, 8/15)))

        # Reset U and J from previous step
        _reset_particles(pfield)

        # Calculate interactions between particles: U and J
        pfield.UJ(pfield)

        # Calculate subgrid-scale contributions
        _reset_particles_sgs(pfield)
        pfield.sgsmodel(pfield)

        # Update the particle field: convection and stretching
        for p in iterator(pfield)

            # Low-storage RK step
            ## Velocity
            p.M[1, 1] = a*p.M[1, 1] + dt*(p.U[1] + Uinf[1])
            p.M[2, 1] = a*p.M[2, 1] + dt*(p.U[2] + Uinf[2])
            p.M[3, 1] = a*p.M[3, 1] + dt*(p.U[3] + Uinf[3])

            # Update position
            p.X[1] += b*p.M[1, 1]
            p.X[2] += b*p.M[2, 1]
            p.X[3] += b*p.M[3, 1]

            # Store stretching S under M[1:3]
            if pfield.transposed
                # Transposed scheme S = (Γ⋅∇')U
                MM[1] = (p.J[1,1]*p.Gamma[1]+p.J[2,1]*p.Gamma[2]+p.J[3,1]*p.Gamma[3])
                MM[2] = (p.J[1,2]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[3,2]*p.Gamma[3])
                MM[3] = (p.J[1,3]*p.Gamma[1]+p.J[2,3]*p.Gamma[2]+p.J[3,3]*p.Gamma[3])
            else
                # Classic scheme (Γ⋅∇)U
                MM[1] = (p.J[1,1]*p.Gamma[1]+p.J[1,2]*p.Gamma[2]+p.J[1,3]*p.Gamma[3])
                MM[2] = (p.J[2,1]*p.Gamma[1]+p.J[2,2]*p.Gamma[2]+p.J[2,3]*p.Gamma[3])
                MM[3] = (p.J[3,1]*p.Gamma[1]+p.J[3,2]*p.Gamma[2]+p.J[3,3]*p.Gamma[3])
            end

            # Store Z under MM[4] with Z = [ (f+g)/(1+3f) * S⋅Γ + f/(1+3f) * M3⋅Γ ] / mag(Γ)^2
            MM[4] = (f+g)/(1+3*f) * (MM[1]*p.Gamma[1] + MM[2]*p.Gamma[2] + MM[3]*p.Gamma[3])
            MM[4] += f/(1+3*f) * (getproperty(p, _SGS)[1]*p.Gamma[1]
                                    + getproperty(p, _SGS)[2]*p.Gamma[2]
                                    + getproperty(p, _SGS)[3]*p.Gamma[3])
            MM[4] /= p.Gamma[1]^2 + p.Gamma[2]^2 + p.Gamma[3]^2

            # Store qstr_i = a_i*qstr_{i-1} + ΔΓ,
            # with ΔΓ = Δt*( S - 3ZΓ + M3 )
            p.M[1, 2] = a*p.M[1, 2] + dt*(MM[1] - 3*MM[4]*p.Gamma[1] + getproperty(p, _SGS)[1])
            p.M[2, 2] = a*p.M[2, 2] + dt*(MM[2] - 3*MM[4]*p.Gamma[2] + getproperty(p, _SGS)[2])
            p.M[3, 2] = a*p.M[3, 2] + dt*(MM[3] - 3*MM[4]*p.Gamma[3] + getproperty(p, _SGS)[3])

            # Store qsgm_i = a_i*qsgm_{i-1} + Δσ, with Δσ = -Δt*σ*Z
            p.M[2, 3] = a*p.M[2, 3] - dt*( p.sigma[1] * MM[4] )

            # Update vectorial circulation
            p.Gamma[1] += b*p.M[1, 2]
            p.Gamma[2] += b*p.M[2, 2]
            p.Gamma[3] += b*p.M[3, 2]

            # Update cross-sectional area
            p.sigma[1] += b*p.M[2, 3]

        end

        # Update the particle field: viscous diffusion
        viscousdiffusion(pfield, dt; aux1=a, aux2=b)

    end


    # Relaxation: Align vectorial circulation to local vorticity
    if relax

        # Resets U and J from previous step
        _reset_particles(pfield)

        # Calculates interactions between particles: U and J
        # NOTE: Technically we have to calculate J at the final location,
        #       but in MyVPM I just used the J calculated in the last RK step
        #       and it worked just fine. So maybe I perhaps I can save computation
        #       by not calculating UJ again.
        pfield.UJ(pfield)

        for p in iterator(pfield)
            # Align particle strength
            pfield.relaxation(pfield.rlxf, p)
        end
    end

    return nothing
end






"""
    `relaxation_Pedrizzetti(rlxf::Real, p::Particle)`

Relaxation scheme where the vortex strength is aligned with the local vorticity.
"""
function relaxation_pedrizzetti(rlxf::Real, p::Particle)

    nrmw = sqrt( (p.J[3,2]-p.J[2,3])*(p.J[3,2]-p.J[2,3]) +
                    (p.J[1,3]-p.J[3,1])*(p.J[1,3]-p.J[3,1]) +
                    (p.J[2,1]-p.J[1,2])*(p.J[2,1]-p.J[1,2]))
    nrmGamma = sqrt(p.Gamma[1]^2 + p.Gamma[2]^2 + p.Gamma[3]^2)

    p.Gamma[1] = (1-rlxf)*p.Gamma[1] + rlxf*nrmGamma*(p.J[3,2]-p.J[2,3])/nrmw
    p.Gamma[2] = (1-rlxf)*p.Gamma[2] + rlxf*nrmGamma*(p.J[1,3]-p.J[3,1])/nrmw
    p.Gamma[3] = (1-rlxf)*p.Gamma[3] + rlxf*nrmGamma*(p.J[2,1]-p.J[1,2])/nrmw

    return nothing
end


"""
    `relaxation_correctedPedrizzetti(rlxf::Real, p::Particle)`

Relaxation scheme where the vortex strength is aligned with the local vorticity.
This version fixes the error in Pedrizzetti's relaxation that made the strength
to continually decrease over time. See notebook 20200921 for derivation.
"""
function relaxation_correctedpedrizzetti(rlxf::Real, p::Particle)

    nrmw = sqrt( (p.J[3,2]-p.J[2,3])*(p.J[3,2]-p.J[2,3]) +
                    (p.J[1,3]-p.J[3,1])*(p.J[1,3]-p.J[3,1]) +
                    (p.J[2,1]-p.J[1,2])*(p.J[2,1]-p.J[1,2]))
    nrmGamma = sqrt(p.Gamma[1]^2 + p.Gamma[2]^2 + p.Gamma[3]^2)

    b2 =  1 - 2*(1-rlxf)*rlxf*(1 - (
                                                    p.Gamma[1]*(p.J[3,2]-p.J[2,3]) +
                                                    p.Gamma[2]*(p.J[1,3]-p.J[3,1]) +
                                                    p.Gamma[3]*(p.J[2,1]-p.J[1,2])
                                                  ) / (nrmGamma*nrmw))

    p.Gamma[1] = (1-rlxf)*p.Gamma[1] + rlxf*nrmGamma*(p.J[3,2]-p.J[2,3])/nrmw
    p.Gamma[2] = (1-rlxf)*p.Gamma[2] + rlxf*nrmGamma*(p.J[1,3]-p.J[3,1])/nrmw
    p.Gamma[3] = (1-rlxf)*p.Gamma[3] + rlxf*nrmGamma*(p.J[2,1]-p.J[1,2])/nrmw

    # Normalize the direction of the new vector to maintain the same strength
    p.Gamma ./= sqrt(b2)

    return nothing
end
