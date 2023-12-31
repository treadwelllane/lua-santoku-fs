local env = {

  name = "santoku-fs",
  version = "0.0.12-1",
  variable_prefix = "TK_FS",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.158-1",
  },

  test = {
    dependencies = {
      "santoku-test >= 0.0.6-1",
      "luassert >= 1.9.0-1",
      "luacov >= scm-1",
    }
  },

}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  type = "lib",
  env = env,
}
