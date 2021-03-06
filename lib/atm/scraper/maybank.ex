defmodule Atm.Scraper.Maybank do
  alias Atm.{Repo, Bank, Location}
  import Ecto.Query, only: [from: 2, first: 1]

  def perform(type) do
    %HTTPoison.Response{body: html} = HTTPoison.get!("http://www.maybank2u.com.my/mbb_info/m2u/public/customerService.do?programId=CS-CustService&chCatId=/mbb/Personal")

    bank =
      from(b in Bank, where: b.name == "Maybank")
      |> first
      |> Repo.one

    parse(html, bank, type)
  end

  def parse(html, bank, type) do
    html
    |> Floki.find("select")
    |> Enum.at(1)
    |> Floki.find("option")
    |> Enum.filter(&filter_state/1)
    |> iterate_states(bank, type)
  end

  def parse(html, bank) do
    headings = Floki.find(html, "#leftCol h3")
    tables = Floki.find(html, "#mainColomn > #leftCol > table")

    Enum.each(headings, fn heading ->
      name =
        heading
        |> Floki.text
        |> String.strip

      index = Enum.find_index(headings, &(&1 == heading))

      address =
        tables
        |> Enum.at(index)
        |> Floki.find("td")
        |> Enum.at(2)
        |> Floki.raw_html
        |> String.split("<strong>Facilities</strong>")
        |> hd
        |> Floki.text
        |> String.replace("\r", "")
        |> String.replace("\t", "")
        |> String.replace("\n\n\n\n\n", "\n")
        |> String.replace("\n\n\n\n", "\n")
        |> String.replace("\n\n\n", "\n")
        |> String.replace("\n\n", "\n")
        |> String.replace("\n", " ")
        |> String.strip

      location =
        from(l in Location, where: l.name == ^name)
        |> first
        |> Repo.one

      if String.valid?(address) and is_nil(location) do
        location = Ecto.build_assoc(bank, :locations)
        changeset = Location.changeset_without_coordinate(location, %{name: name, address: address})

        case Repo.insert(changeset) do
          {:ok, location} ->
            IO.inspect location

          {:error, _changeset} ->
            nil
        end
      end
    end)
  end

  def filter_state(option) do
    [value] = Floki.attribute(option, "value")
    value != ""
  end

  def iterate_states(options, bank, type) do
    Enum.each(options, fn option ->
      [state] = Floki.attribute(option, "value")

      %HTTPoison.Response{body: html} = HTTPoison.get!("http://www.maybank2u.com.my/mbb_info/m2u/public/customerServiceBranchDetailsList.do", [], params: [
        state: state,
        branch: type_to_binary(type),
        channelId: "",
        cs: 1,
        programId: "CS-CustService",
        chCatId: "/mbb/Personal"
      ])

      parse(html, bank)
    end)
  end

  def type_to_binary(:branch), do: "Branches"
  def type_to_binary(:offsite), do: "ATM off branch"

end
