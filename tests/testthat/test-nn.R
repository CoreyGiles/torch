context("nn")

test_that("nn_module", {
  my_net <- nn_module(
    "my_net",
    initialize = function(n_inputs, n_outputs) {
      self$W <- nn_parameter(torch_randn(n_inputs, n_outputs))
      self$b <- nn_parameter(torch_zeros(n_outputs))
    },
    forward = function(x) {
      torch_addmm(self$b, x, self$W)
    }
  )

  model <- my_net(1, 1)
  expect_s3_class(model, "nn_module")
  expect_s3_class(model, "my_net")
  expect_length(model$parameters, 2)
  expect_tensor(model(torch_randn(10, 1)))
})

test_that("nn_modules can have child modules", {
  my_net <- nn_module(
    "my_net",
    initialize = function(n_inputs, n_outputs) {
      self$linear <- nn_linear(n_inputs, n_outputs)
    },
    forward = function(x) {
      self$linear(x)
    }
  )

  model <- my_net(1, 2)
  x <- torch_randn(1, 1)
  output <- model(x)

  expect_s3_class(model, "nn_module")
  expect_s3_class(model, "my_net")
  expect_length(model$parameters, 2)
  expect_tensor(output)
  expect_equal(output$dim(), 2)
})

test_that("nn_sequential", {
  model <- nn_sequential(
    nn_linear(10, 100),
    nn_relu(),
    nn_linear(100, 1)
  )

  input <- torch_randn(1000, 10)
  output <- model(input)

  expect_tensor(output)
  expect_s3_class(model, "nn_sequential")
  expect_s3_class(model, "nn_module")
  expect_equal(output$shape, c(1000, 1))
  expect_length(model$parameters, 4)

  my_sequential <- nn_module(inherit = nn_sequential, classname = "mynet")

  model <- my_sequential(
    nn_linear(10, 100),
    nn_relu(),
    nn_linear(100, 1)
  )

  expect_s3_class(model, "mynet")
  expect_s3_class(model, "nn_module")
})

test_that("nn_sequential only accepts modules", {
  expect_error(nn_sequential(identity), "but got object of type")
  expect_error(nn_sequential(nn_linear), "must be initialized")
})

test_that("nn_module_list", {
  x <- nn_module_list(list(
    nn_linear(10, 100),
    nn_relu(),
    nn_linear(100, 10)
  ))

  expect_s3_class(x[[1]], "nn_linear")
  expect_s3_class(x[[2]], "nn_relu")
  expect_s3_class(x[[3]], "nn_linear")

  x$append(nn_relu6())
  expect_s3_class(x[[4]], "nn_relu6")

  x$extend(list(nn_celu(), nn_gelu()))
  expect_s3_class(x[[5]], "nn_celu")
  expect_s3_class(x[[6]], "nn_gelu")

  x$insert(index = 1, nn_dropout())
  expect_s3_class(x[[1]], "nn_dropout")

  expect_length(x, 7)
})

test_that("as.list.nn_module_list", {
  x <- nn_module_list(list(
    nn_linear(10, 100),
    nn_relu(),
    nn_linear(100, 10)
  ))

  x_list <- as.list(x)

  expect_length(x_list, 3)
  expect_type(x_list, "list")
  expect_s3_class(x_list[[1]], "nn_linear")
  expect_s3_class(x_list[[2]], "nn_relu")
  expect_s3_class(x_list[[3]], "nn_linear")
})

test_that("module_list inside a module", {
  my_module <- nn_module(
    initialize = function() {
      self$linears <- nn_module_list(lapply(1:10, function(x) nn_linear(10, 10)))
    },
    forward = function(x) {
      for (i in 1:length(self$linears)) {
        x <- self$linears[[i]](x)
      }
      x
    }
  )

  m <- my_module()
  expect_length(m$parameters, 20)
  output <- m(torch_randn(5, 10))
  expect_tensor(output)
})

test_that("to", {
  net <- nn_linear(10, 10)
  net$to(dtype = torch_double())

  expect_true(net$weight$dtype == torch_double())
  expect_true(net$bias$dtype == torch_double())


  Net <- nn_module(
    initialize = function() {
      self$linear <- nn_linear(10, 1)
      self$norm <- nn_batch_norm1d(1)
    },
    forward = function(x) {
      x <- self$linear(x)
      x <- self$norm(x)
      x
    }
  )
  net <- Net()
  x <- torch_randn(10, 10)
  y <- net(x)
  r <- torch_mean(y)
  r$backward()

  net$to(dtype = torch_double())

  expect_true(net$linear$weight$dtype == torch_double())
  expect_true(net$linear$bias$dtype == torch_double())
  expect_true(net$norm$running_mean$dtype == torch_double())
  expect_true(net$norm$running_var$dtype == torch_double())
  expect_true(net$linear$weight$grad$dtype == torch_double())

  skip_if_cuda_not_available()
  net$cuda()
  expect_equal(net$linear$weight$device$type, "cuda")
  expect_equal(net$linear$bias$device$type, "cuda")

  net$cpu()
  expect_equal(net$linear$weight$device$type, "cpu")
  expect_equal(net$linear$bias$device$type, "cpu")
})

test_that("state_dict for modules", {
  Net <- nn_module(
    initialize = function() {
      self$linear <- nn_linear(10, 1)
      self$norm <- nn_batch_norm1d(1)
    },
    forward = function(x) {
      x <- self$linear(x)
      x <- self$norm(x)
      x
    }
  )
  net <- Net()
  s <- net$state_dict()
  s

  expect_length(s, 7)
  expect_equal_to_tensor(s[[1]], net$linear$weight)
  expect_equal_to_tensor(s[[2]], net$linear$bias)
  expect_equal_to_tensor(s[[5]], net$norm$running_mean)
  expect_equal_to_tensor(s[[6]], net$norm$running_var)

  net2 <- Net()
  net2$load_state_dict(s)
  s <- net2$state_dict()

  expect_length(s, 7)
  expect_equal_to_tensor(s[[1]], net$linear$weight)
  expect_equal_to_tensor(s[[2]], net$linear$bias)
  expect_equal_to_tensor(s[[5]], net$norm$running_mean)
  expect_equal_to_tensor(s[[6]], net$norm$running_var)


  s <- s[-6]
  expect_error(net2$load_state_dict(s), class = "value_error")
})

test_that("zero_grad", {
  Net <- nn_module(
    initialize = function() {
      self$linear <- nn_linear(10, 1)
      self$norm <- nn_batch_norm1d(1)
    },
    forward = function(x) {
      x <- self$linear(x)
      x <- self$norm(x)
      x
    }
  )
  net <- Net()

  expect_no_error(net$zero_grad())
  expect_true(is_undefined_tensor(net$linear$weight$grad))

  x <- torch_randn(500, 10)
  l <- torch_mean((x - net(x)*2 + 100)^2)
  l$backward()

  expect_false(as_array(torch_all(net$linear$weight$grad == 0)))
  expect_false(as_array(torch_all(net$linear$bias$grad == 0)))
  expect_false(as_array(torch_all(net$norm$weight$grad == 0)))
  expect_false(as_array(torch_all(net$norm$bias$grad == 0)))

  net$zero_grad()

  expect_true(as_array(torch_all(net$linear$weight$grad == 0)))
  expect_true(as_array(torch_all(net$linear$bias$grad == 0)))
  expect_true(as_array(torch_all(net$norm$weight$grad == 0)))
  expect_true(as_array(torch_all(net$norm$bias$grad == 0)))
})

test_that("index modules with integers", {
  Net <- nn_module(
    initialize = function() {
      self$linear <- nn_linear(10, 1)
      self$norm <- nn_batch_norm1d(1)
    },
    forward = function(x) {
      x <- self$linear(x)
      x <- self$norm(x)
      x
    }
  )
  net <- Net()

  expect_equal_to_tensor(net[[1]]$weight, net$linear$weight)

  net <- nn_linear(10, 10)

  expect_error(net[[1]], "out of bounds")
})

test_that("to still returns an nn_module", {
  x <- nn_linear(10, 10)
  y <- x$to(device = "cpu")

  expect_s3_class(y, "nn_module")

  expect_tensor_shape(y(torch_randn(10, 10)), c(10, 10))
})

test_that("moodule$apply", {
  Net <- nn_module(
    initialize = function() {
      self$linear <- nn_linear(10, 1)
      self$norm <- nn_batch_norm1d(1)
    },
    forward = function(x) {
      x <- self$linear(x)
      x <- self$norm(x)
      x
    }
  )

  net <- Net()
  zero <- function(x) {
    if (!is.null(x$weight)) {
      with_no_grad({
        x$weight$zero_()
      })
    }
  }
  net$apply(zero)

  expect_equal_to_tensor(net$linear$weight, torch_zeros_like(net$linear$weight))
  expect_equal_to_tensor(net$norm$weight, torch_zeros_like(net$norm$weight))
})

test_that("$<-  works for instances", {
  m <- nn_module(
    initialize = function() {
      self$mymodule <- nn_linear(10, 10)
      self$n <- nn_linear(15, 15)
    }
  )

  model <- m()
  expect_s3_class(model, "nn_module")
  model$mymodule <- nn_linear(2, 2)
  expect_s3_class(model, "nn_module")
  expect_equal(model$mymodule$out_features, 2)
  model$new_module <- nn_linear(5, 5)
  expect_s3_class(model, "nn_module")

  pars <- model$parameters
  expect_length(pars, 6)
  expect_tensor_shape(pars$mymodule.weight, c(2, 2))
  expect_tensor_shape(pars$new_module.weight, c(5, 5))
})

test_that("[[<- works for instances", {
  m <- nn_module(
    initialize = function() {
      self$mymodule <- nn_linear(10, 10)
      self$n <- nn_linear(15, 15)
    }
  )

  model <- m()
  expect_s3_class(model, "nn_module")
  model[["mymodule"]] <- nn_linear(2, 2)
  expect_s3_class(model, "nn_module")
  expect_equal(model$mymodule$out_features, 2)
  model[["new_module"]] <- nn_linear(5, 5)
  expect_s3_class(model, "nn_module")

  pars <- model$parameters
  expect_length(pars, 6)
  expect_tensor_shape(pars$mymodule.weight, c(2, 2))
  expect_tensor_shape(pars$new_module.weight, c(5, 5))
})

test_that("nn_module_list names", {
  mod <- nn_module(
    initialize = function() {
      self$k <- nn_module_list()
      self$k$append(nn_linear(10, 10))
      self$k$extend(list(nn_linear(10, 10)))
    }
  )
  m <- mod()
  expect_equal(
    names(m$state_dict()),
    c("k.0.weight", "k.0.bias", "k.1.weight", "k.1.bias")
  )
})

test_that("deduplicate duplicated parameters", {
  m <- nn_module(
    initialize = function(x) {
      x <- nn_linear(10, 10)
      self$x <- x
      self$y <- x
    }
  )
  expect_length(m()$parameters, 2)
  expect_named(m()$parameters, c("x.weight", "x.bias"))
})

test_that("allow nn_modules with private and active methods", {
  x <- nn_module(
    "my_module",
    initialize = function() {
      self$dense <- nn_linear(10, 1)
      private$dense2 <- nn_linear(10, 1)
    },
    forward = function(input) {
      list(
        self$dense(input) + private$constant(),
        private$dense2(input) + self$constant2
      )
    },
    private = list(
      constant = function() {
        torch_tensor(10)
      }
    ),
    active = list(
      constant2 = function() {
        torch_tensor(5)
      }
    )
  )

  m <- x()

  expect_error(
    o <- m(torch_randn(100, 10)),
    regexp = NA
  )

  expect_tensor_shape(o[[1]], c(100, 1))
  expect_tensor_shape(o[[2]], c(100, 1))
})

test_that("print method works", {
  local_edition(3)
  skip_on_os("windows")
  skip_on_os("linux")

  my_module <- nn_module(
    initialize = function() {
      self$linear <- nn_linear(10, 10)
      self$linear2 <- nn_linear(10, 1)
      self$x <- nn_parameter(torch_randn(10, 10))
      self$k <- nn_buffer(torch_randn(5, 5))
    },
    forward = function(x) {
      x %>%
        self$linear() %>%
        self$linear2()
    }
  )

  withr::with_options(
    new = c(cli.width = 50),
    expect_snapshot_output(my_module())
  )
})

test_that("error when trying to modify the parameter list", {
  x <- nn_linear(10, 10)

  expect_error(
    x$parameters <- list(1),
    class = "runtime_error",
    regexp = "It's not possible"
  )

  expect_error(
    x$parameters$weight <- torch_tensor(1),
    class = "runtime_error",
    regexp = "It's not possible"
  )
})

test_that("modules method", {
  custom1 <- nn_module(
    "myname",
    initialize = function() {
      self$x <- nn_linear(10, 10)
      self$y <- self$x
    }
  )

  mod <- nn_module(
    initialize = function() {
      self$c1 <- custom1()
      self$fc <- nn_linear(5, 5)
    }
  )

  model <- mod()

  expect_length(model$modules, 4)
  expect_identical_modules(model$modules[[1]], model)
  expect_identical_modules(model$modules[[2]], model$c1)
  expect_identical_modules(model$modules[[3]], model$c1$x)
  expect_identical_modules(model$modules[[4]], model$fc)

  expect_error(
    model$modules <- list(nn_linear(10, 10)),
    class = "runtime_error"
  )
})

test_that("length for sequential modules", {
  m <- nn_sequential(
    nn_conv2d(10, 10, c(5, 5)),
    nn_conv2d(10, 10, c(5, 5))
  )

  expect_length(m, 2)

  z <- nn_sequential(
    m,
    nn_conv2d(2, 2, c(5, 5)),
    nn_conv2d(2, 2, c(5, 5))
  )

  expect_length(z, 3)
})

test_that("train/eval returns a callable module", {
  mod <- nn_module(initialize = identity, forward = identity)
  m <- mod(1)

  expect_s3_class(m$eval(), "nn_module")
  expect_s3_class(m$train(), "nn_module")
})

test_that("calling to doesn't modify the requires_grad attribute of a parameter", {

  # see https://github.com/mlverse/torch/issues/491

  x <- nn_linear(1, 1)
  expect_true(x$weight$requires_grad)
  x$weight$requires_grad_(FALSE)
  expect_true(!x$weight$requires_grad)
  x$to(device = "cpu")
  expect_true(!x$weight$requires_grad)


  skip_if_cuda_not_available()
  x <- nn_linear(1, 1)
  expect_true(x$weight$requires_grad)
  x$to(device = "cuda")
  expect_true(x$weight$requires_grad)

  x <- nn_linear(1, 1)
  expect_true(x$weight$requires_grad)
  x$weight$requires_grad_(FALSE)
  expect_true(!x$weight$requires_grad)
  x$to(device = "cuda")
  expect_true(!x$weight$requires_grad)
})

test_that("we can subset `nn_sequential`", {
  x <- nn_sequential(
    nn_relu(),
    nn_tanh(),
    nn_relu6(),
    nn_relu(),
    nn_tanh()
  )

  expect_true(inherits(x[[1]], "nn_relu"))
  expect_true(inherits(x[[3]], "nn_relu6"))

  y <- x[2:4]
  expect_true(inherits(y, "nn_sequential"))
  expect_true(inherits(y[[1]], "nn_tanh"))
  expect_true(inherits(y[[2]], "nn_relu6"))
})

test_that("we can prune head of `nn_sequential`", {
  x <- nn_sequential(
    nn_relu(),
    nn_tanh(),
    nn_relu6(),
    nn_relu(),
    nn_tanh(),
    nn_linear(10,3)
  )
  expect_error(prune <- nn_prune_head(x), NA)
  expect_true(inherits(prune, "nn_sequential"))
  expect_equal(length(prune), 5)
})

test_that("we can prune head of `nn_sequential` by 3 layers", {
  x <- nn_sequential(
    nn_relu(),
    nn_tanh(),
    nn_relu6(),
    nn_relu(),
    nn_linear(2,10),
    nn_batch_norm1d(10),
    nn_tanh(),
    nn_linear(10,3)
  )
  expect_error(prune <- nn_prune_head(x, 3), NA)
  expect_true(inherits(prune, "nn_sequential"))
  expect_equal(length(prune), 5)
  expect_true(inherits(prune[[length(prune)]], "nn_linear"))
})

test_that("we can prune head of `nn_module` network", {
  my_net <- nn_module(
    "my_net",
    initialize = function(n_inputs, n_outputs) {
      self$linear <- nn_linear(n_inputs, n_outputs)
      self$head <- nn_linear(n_outputs, 2)
    },
    forward = function(x) {
      x <- self$linear(x)
      self$head(x)
    }
  )

  x <- my_net(1, 3)

  expect_error(prune <- nn_prune_head(x, 1), NA)
  expect_true(inherits(prune, "nn_sequential"))
  expect_equal(length(prune), 1)
  expect_true(inherits(prune[[length(prune)]], "nn_linear"))
  input <- torch::torch_randn(5, 1)
  out <- prune(input)
  expect_tensor_shape(out, c(5, 3))
})

test_that("classes are inherited correctly", {
  nn <- nn_module(
    classname = "hello",
    inherit = nn_linear
  )

  nn2 <- nn_module(
    classname = "goodbye",
    inherit = nn
  )

  expect_equal(
    class(nn), c("hello", "nn_linear", "nn_module", "nn_module_generator")
  )

  expect_equal(
    class(nn2), c("goodbye", "hello", "nn_linear", "nn_module", "nn_module_generator")
  )

  n <- nn(10, 10)
  expect_equal(class(n), c("hello", "nn_linear", "nn_module"))
  n2 <- nn2(10, 10)
  expect_equal(class(n2), c("goodbye", "hello", "nn_linear", "nn_module"))
})

test_that("empty initializer", {
  model <- nn_module(forward = function(input) input)
  expect_equal_to_r(model()(torch_tensor(1)), 1)
})

test_that("can load state dict of a corrupt module", {
  local_edition(3)

  model <- nn_linear(10, 10)
  tmp <- tempfile(fileext = "rds")
  saveRDS(model, tmp)
  rm(model); gc();
  model <- readRDS(tmp)

  err <- try({model$parameters$weight$abs()}, silent = TRUE)
  expect_true(inherits(err, "try-error"))

  expect_error(regexp = NA, {
    model$load_state_dict(list(weight = torch_randn(10, 10), bias = torch_randn(10)))
  })

  expect_tensor_shape(model(torch_randn(10, 10)), c(10, 10))
})

test_that("make sure state_dict() is detached", {
  model <- nn_linear(10, 10)
  model$bias$requires_grad_(FALSE)
  state_dict <- model$state_dict()

  expect_true(state_dict$weight$requires_grad)
  # we should keep the save value of requires grad bt in a detached graph
  expect_false(state_dict$bias$requires_grad)
})

test_that("deep cloning", {

  x <- nn_linear(1, 1)
  y <- x$clone(deep = TRUE)

  expect_true(xptr_address(x$parameters$weight) != xptr_address(y$parameters$weight))
  expect_equal_to_tensor(x(torch_ones(1,1)), y(torch_ones(1,1)))

  module <- nn_module(
    initialize = function() {
      self$x <- nn_parameter(torch_tensor(1))
      self$y <- self$x
      self$a <- nn_buffer(torch_tensor(1))
      self$b <- self$a
    }
  )

  x <- module()
  y <- x$clone(deep = TRUE)

  expect_true(xptr_address(x$x) != xptr_address(y$x))
  expect_true(xptr_address(x$y) != xptr_address(y$y))
  expect_true(xptr_address(y$x) == xptr_address(y$y))

  expect_true(xptr_address(x$a) != xptr_address(y$a))
  expect_true(xptr_address(x$b) != xptr_address(y$b))
  expect_true(xptr_address(y$a) == xptr_address(y$b))

  module <- nn_module(
    initialize = function() {
      self$x <- nn_linear(1, 1)
      self$y <- self$x
    }
  )

  x <- module()
  y <- x$clone(deep = TRUE)
  expect_true(xptr_address(x$x$weight) != xptr_address(y$x$weight))
  expect_true(xptr_address(x$y$weight) != xptr_address(y$y$weight))
  expect_true(xptr_address(y$x$weight) == xptr_address(y$y$weight))

  expect_true(rlang::obj_address(x$x) != rlang::obj_address(y$x))
  expect_true(rlang::obj_address(y$x) == rlang::obj_address(y$y))

  # make sure we re-lock binding
  expect_true(bindingIsLocked("clone", attr(x, "module")))

  # make sure the class of parameters remains
  a <- nn_linear(1, 1)
  b <- a$clone(deep = TRUE)

  expect_equal(
    attributes(b$parameters$weight),
    attributes(a$parameters$weight)
  )
})

test_that("Can initialize a model in the meta device and copy parameters to it", {

  with_device(device="meta", {
    model <- nn_linear(10,10)
  })
  expect_equal(model$weight$device$type, "meta")
  expect_true(model$weight$requires_grad)
  model$bias$requires_grad_(FALSE)
  expect_true(!model$bias$requires_grad)

  model2 <- nn_linear(10, 10)
  model$load_state_dict(model2$state_dict(), .refer_to_state_dict = TRUE)
  expect_equal(model$weight$device$type, "cpu")
  expect_equal(length(model$parameters), 2)
  expect_true(model$weight$requires_grad)
  expect_true(!model$bias$requires_grad)

  # now let's test with a more complex model that includes a batch_norm.
  net <- nn_module(
    "Net",
    initialize = function() {
      self$features <- nn_sequential(
        nn_conv2d(3, 5, kernel_size = 11, stride = 4, padding = 2),
        nn_relu()
      )
      self$avgpool <- nn_max_pool2d(c(6, 6))
      self$batch_norm <- nn_batch_norm2d(11)
      self$classifier <- nn_sequential(
        nn_dropout(),
        nn_linear(10, 10),
        nn_relu(),
        nn_dropout()
      )
    },
    forward = function(x) {
      x <- self$features(x)
      x <- self$avgpool(x)
      x <- torch_flatten(x, start_dim = 2)
      x <- self$classifier(x)
    }
  )

  with_device(device="meta", {
    model <- net()
  })

  expect_true(all(sapply(model$parameters, function(x) x$device$type) == "meta"))

  model2 <- net()
  model$load_state_dict(model2$state_dict(), .refer_to_state_dict = TRUE)

  state_dict1 <- model$state_dict()
  state_dict2 <- model2$state_dict()

  for(i in seq_along(state_dict1)) {
    expect_equal_to_tensor(state_dict1[[i]], state_dict2[[i]])
  }

})

test_that("non persistent buffers work correctly", {
  module <- nn_module(
    initialize = function() {
      self$x <- nn_parameter(torch_tensor(1))
      self$y <- nn_buffer(torch_tensor(2))
      self$z <- nn_buffer(torch_tensor(3), persistent = FALSE)
    },
    forward = function() {
      self$x + self$y + self$z
    }
  )

  model <- module()
  expect_true(all(names(model$state_dict()) %in% c("x", "y")))
  expect_error(
    model$load_state_dict(list(x = torch_tensor(1), y = torch_tensor(2))),
    regexp = NA
  )
})

test_that("can use a named module dict", {

  dict <- nn_module_dict(list(
    x = nn_linear(1, 10),
    y = nn_linear(10, 1)
  ))

  x <- torch_randn(100,1)
  y <- dict$x(x)
  z <- dict$y(y)

  expect_tensor_shape(z, c(100, 1))
  expect_equal(length(dict$parameters), 4)
})

test_that("can clone a module with no state dict", {

  expect_no_error({
    nn_relu()$clone(TRUE)
  })

})

test_that("clone preserves requires_grad", {
  lin <- nn_linear(1, 1)
  expect_equal(lin$weight$requires_grad, lin$clone(deep = TRUE)$weight$requires_grad)

  lin$weight$requires_grad_(FALSE)
  expect_equal(lin$weight$requires_grad, lin$clone(deep = TRUE)$weight$requires_grad)
})

test_that("can clone module after calling $train() or $eval()", {
  expect_true(inherits(nn_linear(1, 1)$train()$clone(deep = TRUE), "nn_module"))
  expect_true(inherits(nn_linear(1, 1)$eval()$clone(deep = TRUE), "nn_module"))
})

test_that("weights of cloned module don't contain CloneBackward0 grad_fn", {
  # note that this differs from the cloning of a tensor, which adds the CloneBackward grad_fn
  # The python equivalent to the $clone() method for nn_modules would be the copy.(deep)copy function in python
  n <- nn_linear(1, 1)
  n1 <- n$clone(deep = TRUE)
  expect_true(is.null(n1$weight$grad_fn))
})

test_that("repeated clone works", {
  n <- nn_linear(1, 1)
  n1 <- n$clone(deep = TRUE)
  n2 <- n1$clone(deep = TRUE)
  expect_equal(attr(n, "module")$clone, attr(n1, "module")$clone)
  expect_equal(attr(n, "module")$clone, attr(n2, "module")$clone)
})

test_that("can finalize cloning", {
  nn_test <- nn_module("test", initialize = function() {
    self$lin <- nn_linear(1, 10)
    },
    forward = function(x) {
      self$lin(x)
    },
    private = list(
      finalize_deep_clone = function() {
        self$new_val <- 1
      }
    )
  )()

  nn_test1 <- nn_test$clone(deep = TRUE)
  expect_equal(nn_test1$new_val, 1)
  expect_false(isTRUE(all.equal(nn_test$new_val, 1)))
})

test_that("children are properly cloned", {
  nn_test <- nn_module("test", initialize = function() {
    self$l <- nn_module_list(list(nn_linear(1, 1)))
    },
    forward = function(x) {
      self$l[[1]](x)
    }
  )()

  nn_test1 <- nn_test$clone(deep = TRUE)
  l1 <- nn_test$l$modules[[2]]
  l2 <- nn_test1$l$modules[[2]]
  expect_false(identical(
    l1$parameters,
    l2$parameters
  ))
  expect_false(identical(l1, l2))
})

test_that("non-persistent buffers are cloned", {
  n <- nn_identity()
  n$register_buffer("a", nn_buffer(torch_tensor(1)), persistent = FALSE)
  n1 <- n$clone(deep = TRUE)
  expect_false(identical(n$buffers, n1$buffers))
})
