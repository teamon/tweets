Mix.install([
  {:ecto, "~> 3.0"},
  {:ecto_sqlite3, "~> 0.10"}
])

Application.put_env(:myapp, Repo, database: "myapp.db")

defmodule Repo do
  use Ecto.Repo, otp_app: :myapp, adapter: Ecto.Adapters.SQLite3
end

defmodule Migration0 do
  use Ecto.Migration

  def change do
    create table("users") do
      add(:name, :string)
    end
  end
end

defmodule User do
  use Ecto.Schema

  schema "users" do
    field(:name, :string)
  end
end

defmodule Operation do
  @type mode :: :real | :dryrun

  @spec run(mode, op :: (() -> any)) ::
          {:ok, any}
          | {:error, {:dryrun, any}}
          | {:error, any}
  def run(mode, op) do
    Repo.transaction(fn ->
      result = op.()

      case mode do
        :real -> result
        :dryrun -> Repo.rollback({:dryrun, result})
      end
    end)
  end
end

defmodule Main do
  def main do
    # reset database
    Repo.__adapter__().storage_down(Repo.config())
    Repo.__adapter__().storage_up(Repo.config())
    {:ok, _} = Repo.start_link()
    Ecto.Migrator.run(Repo, [{0, Migration0}], :up, all: true, log_sql: :debug)

    IO.puts("Dry-Run")
    IO.inspect(Repo.all(User), label: "users before")

    result =
      Operation.run(:dryrun, fn ->
        Repo.insert!(%User{name: "Jon"})
      end)

    IO.inspect(result, label: "result")

    IO.inspect(Repo.all(User), label: "users after")

    IO.puts("Real")
    IO.inspect(Repo.all(User), label: "users before")

    result =
      Operation.run(:real, fn ->
        Repo.insert!(%User{name: "Jon"})
      end)

    IO.inspect(result, label: "result")

    IO.inspect(Repo.all(User), label: "users after")
  end
end

Main.main()
