# flexybayes() reproduces minimal gaussian code byte-identical

    Code
      cat(code)
    Output
      # -- Fixed effects -------------------------------------------
      mu_atg <- normal(0, 10)
      beta_x <- normal(0, 2)
      # -- Residual ------------------------------------------------
      sigma_e_atg <- greta::lognormal(0, 1)
      # -- Linear predictor ----------------------------------------
      mu_i_atg <- mu_atg + beta_x * as_data(x)
      # -- Likelihood ----------------------------------------------
      y_atg_obs <- as_data(y_atg)
      distribution(y_atg_obs) <- normal(mu_i_atg, sigma_e_atg)
      # -- Model and MCMC -----------------------------------------
      atg_model <- greta::model(mu_atg, beta_x, sigma_e_atg)
      atg_draws <- greta::mcmc(atg_model, n_samples = 1000, warmup = 500, chains = 4, verbose = TRUE)

# flexybayes() reproduces simple random-effect code byte-identical

    Code
      cat(code)
    Output
      # -- Fixed effects -------------------------------------------
      mu_atg <- normal(0, 10)
      tau_env <- normal(0, 10, dim = n_env)
      # -- Random effects ------------------------------------------
      sigma_geno <- greta::lognormal(0, 1)
      geno_raw <- normal(0, 1, dim = n_geno)
      u_geno <- geno_raw * sigma_geno
      # -- Residual ------------------------------------------------
      sigma_e_atg <- greta::lognormal(0, 1)
      # -- Linear predictor ----------------------------------------
      mu_i_atg <- mu_atg + tau_env[env_id] + u_geno[geno_id]
      # -- Likelihood ----------------------------------------------
      y_atg_obs <- as_data(y_atg)
      distribution(y_atg_obs) <- normal(mu_i_atg, sigma_e_atg)
      # -- Model and MCMC -----------------------------------------
      atg_model <- greta::model(mu_atg, tau_env, sigma_geno, sigma_e_atg)
      atg_draws <- greta::mcmc(atg_model, n_samples = 1000, warmup = 500, chains = 4, verbose = TRUE)

# flexybayes() reproduces fa_gxe code byte-identical

    Code
      cat(code)
    Output
      # -- Fixed effects -------------------------------------------
      mu_atg <- normal(0, 10)
      tau_env <- normal(0, 10, dim = n_env)
      # -- Random effects ------------------------------------------
      Lambda_geno_env_fa2 <- normal(0, 1, dim = c(n_env, 2L))
      psi_geno_env_fa2    <- greta::lognormal(0, 1, dim = n_env)
      F_geno_env_fa2      <- normal(0, 1, dim = c(n_geno, 2L))
      delta_geno_env_fa2  <- normal(0, 1, dim = c(n_geno, n_env))
      delta_sc_geno_env_fa2 <- sweep(delta_geno_env_fa2, 2, psi_geno_env_fa2, "*")
      g_mat_geno_env_fa2  <- F_geno_env_fa2 %*% t(Lambda_geno_env_fa2) + delta_sc_geno_env_fa2
      # -- Residual ------------------------------------------------
      sigma_e_atg <- greta::lognormal(0, 1)
      # -- Linear predictor ----------------------------------------
      mu_i_atg <- mu_atg + tau_env[env_id] + g_mat_geno_env_fa2[cbind(geno_id, env_id)]
      # -- Likelihood ----------------------------------------------
      y_atg_obs <- as_data(y_atg)
      distribution(y_atg_obs) <- normal(mu_i_atg, sigma_e_atg)
      # -- Model and MCMC -----------------------------------------
      atg_model <- greta::model(mu_atg, tau_env, Lambda_geno_env_fa2, psi_geno_env_fa2, sigma_e_atg)
      atg_draws <- greta::mcmc(atg_model, n_samples = 1000, warmup = 500, chains = 4, verbose = TRUE)

# flexybayes() reproduces at(env):units rcov code byte-identical

    Code
      cat(code)
    Output
      # -- Fixed effects -------------------------------------------
      mu_atg <- normal(0, 10)
      tau_env <- normal(0, 10, dim = n_env)
      # -- Random effects ------------------------------------------
      sigma_geno <- greta::lognormal(0, 1)
      geno_raw <- normal(0, 1, dim = n_geno)
      u_geno <- geno_raw * sigma_geno
      # -- Residual ------------------------------------------------
      sigma_e_atg <- greta::lognormal(0, 1, dim = n_env)
      # -- Linear predictor ----------------------------------------
      mu_i_atg <- mu_atg + tau_env[env_id] + u_geno[geno_id]
      # -- Likelihood ----------------------------------------------
      y_atg_obs <- as_data(y_atg)
      distribution(y_atg_obs) <- normal(mu_i_atg, sigma_e_atg[env_id])
      # -- Model and MCMC -----------------------------------------
      atg_model <- greta::model(mu_atg, tau_env, sigma_geno, sigma_e_atg)
      atg_draws <- greta::mcmc(atg_model, n_samples = 1000, warmup = 500, chains = 4, verbose = TRUE)

# flexybayes() reproduces ar1_spatial code byte-identical

    Code
      cat(code)
    Output
      # -- Fixed effects -------------------------------------------
      mu_atg <- normal(0, 10)
      tau_env <- normal(0, 10, dim = n_env)
      # -- Random effects ------------------------------------------
      sigma_sp_row_col <- greta::lognormal(0, 1)
      sp_row_col_row_raw <- normal(0, 1, dim = n_row)
      sp_row_col_col_raw <- normal(0, 1, dim = n_col)
      u_sp_row_col_row <- sp_row_col_row_raw * sigma_sp_row_col
      u_sp_row_col_col <- sp_row_col_col_raw * sigma_sp_row_col
      # -- Residual ------------------------------------------------
      sigma_e_atg <- greta::lognormal(0, 1)
      # -- Linear predictor ----------------------------------------
      mu_i_atg <- mu_atg + tau_env[env_id] + u_sp_row_col_row[row_id] + u_sp_row_col_col[col_id]
      # -- Likelihood ----------------------------------------------
      y_atg_obs <- as_data(y_atg)
      distribution(y_atg_obs) <- normal(mu_i_atg, sigma_e_atg)
      # -- Model and MCMC -----------------------------------------
      atg_model <- greta::model(mu_atg, tau_env, sigma_sp_row_col, sigma_e_atg)
      atg_draws <- greta::mcmc(atg_model, n_samples = 1000, warmup = 500, chains = 4, verbose = TRUE)

