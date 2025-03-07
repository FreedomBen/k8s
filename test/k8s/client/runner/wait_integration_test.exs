defmodule K8s.Client.Runner.WaitIntegrationTest do
  use ExUnit.Case, async: true
  import K8s.Test.IntegrationHelper

  setup do
    timeout =
      "TEST_WAIT_TIMEOUT"
      |> System.get_env("5")
      |> String.to_integer()

    test_id = :rand.uniform(10_000)
    conn = conn()

    on_exit(fn ->
      delete_job =
        "wait-job-#{test_id}"
        |> job()
        |> K8s.Client.delete()

      K8s.Client.run(conn, delete_job)
    end)

    {:ok, %{conn: conn, test_id: test_id, timeout: timeout}}
  end

  @spec job(binary) :: K8s.Operation.t()
  defp job(name) do
    %{
      "apiVersion" => "batch/v1",
      "kind" => "Job",
      "metadata" => %{"name" => name, "namespace" => "default"},
      "spec" => %{
        "backoffLimit" => 1,
        "template" => %{
          "spec" => %{
            "containers" => [
              %{
                "command" => ["perl", "-Mbignum=bpi", "-wle", "print bpi(3)"],
                "image" => "perl",
                "name" => "pi"
              }
            ],
            "restartPolicy" => "Never"
          }
        }
      }
    }
  end

  @tag integration: true
  test "waiting on a job to finish successfully", %{
    conn: conn,
    test_id: test_id,
    timeout: timeout
  } do
    create_job = "wait-job-#{test_id}" |> job() |> K8s.Client.create()
    {:ok, _} = K8s.Client.run(conn, create_job)

    op = K8s.Client.get("batch/v1", :job, namespace: "default", name: "wait-job-#{test_id}")
    opts = [find: ["status", "succeeded"], eval: 1, timeout: timeout]

    assert {:ok, result} = K8s.Client.Runner.Wait.run(conn, op, opts)
    assert result["status"]["succeeded"] == 1
  end

  @tag integration: true
  test "using an anonymous function to evaluate a job", %{
    conn: conn,
    test_id: test_id,
    timeout: timeout
  } do
    create_job = "wait-job-#{test_id}" |> job() |> K8s.Client.create()
    {:ok, _} = K8s.Client.run(conn, create_job)

    op = K8s.Client.get("batch/v1", :job, namespace: "default", name: "wait-job-#{test_id}")

    eval_fn = fn value_of_status_succeeded ->
      value_of_status_succeeded == 1
    end

    opts = [find: ["status", "succeeded"], eval: eval_fn, timeout: timeout]

    assert {:ok, result} = K8s.Client.Runner.Wait.run(conn, op, opts)
    assert result["status"]["succeeded"] == 1
  end
end
