defmodule Mix.Tasks.Git.Test do
  use Mix.Task

  @moduledoc false

  def run([]), do: git_test(Mix.env())

  def run(_) do
    Mix.raise("git.test does not accept arguments")
  end

  def git_test(:test) do
    cwd = File.cwd!()
    tmpdir = create_tmpdir()

    status("Getting local changes ...")
    diff_file = Path.join(tmpdir, "apply.patch")
    quiet_cmd("sh", ["-c", "git diff --cached --binary > \"#{diff_file}\""])

    status("Cloning tree ...")
    tree = Path.join(tmpdir, "tree")
    quiet_cmd("git", ["clone", cwd, tree])

    if (size = File.stat!(diff_file).size) > 0 do
      status("Applying changes (#{size} bytes) ...")
      quiet_cmd("git", ["apply", "../apply.patch"], cd: tree)
    end

    deps = ["deps" | dependency_build_dirs()]
    status("Linking #{Enum.count(deps)} dependencies ...")
    deps |> Enum.each(&symlink(&1, cwd, tree))

    status("Running tests ...")

    System.cmd("mix", ["test", "--color"], cd: tree, into: IO.stream(:stdio, :line))
    |> check_cmd_result("mix test")

    status("All tests passed.")
  end

  def git_test(_) do
    Mix.raise("Must be run with MIX_ENV=test")
  end

  defp status(text) do
    IO.puts([IO.ANSI.light_green(), "* ", text, IO.ANSI.reset()])
  end

  if Mix.env() == :test do
    defp create_tmpdir do
      {:ok, _started} = Application.ensure_all_started(:briefly)
      {:ok, tmpdir} = Briefly.create(directory: true)
      tmpdir
    end
  else
    defp create_tmpdir, do: raise("not implemented")
  end

  defp symlink(item, from, to) do
    source = Path.join(from, item)
    target = Path.join(to, item)

    Path.dirname(target) |> File.mkdir_p!()
    File.ln_s!(source, target)
  end

  defp dependency_build_dirs do
    lib = Path.join(Mix.Project.build_path(), "lib")

    lib
    |> File.ls!()
    |> Enum.map(&Path.join(lib, &1))
    |> Enum.filter(&File.dir?/1)
    |> List.delete(Mix.Project.app_path())
    |> Enum.map(&Path.relative_to_cwd/1)
  end

  defp quiet_cmd(bin, args, opts \\ []) do
    opts = Keyword.merge([stderr_to_stdout: true], opts)

    System.cmd(bin, args, opts)
    |> check_cmd_result([bin | args] |> Enum.join(" "))
  end

  defp check_cmd_result({_output, 0}, _cmd), do: :ok

  defp check_cmd_result({%IO.Stream{}, code}, cmd) do
    Mix.raise("Command #{inspect(cmd)} exited with status #{code}")
  end

  defp check_cmd_result({output, code}, cmd) do
    IO.puts([
      IO.ANSI.light_red(),
      "---OUTPUT---\n",
      output |> String.trim(),
      "\n---OUTPUT---",
      IO.ANSI.reset()
    ])

    Mix.raise("Command #{inspect(cmd)} exited with status #{code}")
  end
end
