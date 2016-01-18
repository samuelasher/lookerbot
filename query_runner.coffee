_ = require("underscore")

module.exports = class QueryRunner

  constructor: (@looker, @query, @bot, @message, @visualization) ->

  reply: (obj) ->
    @bot.reply(@message, obj)

  run: ->

    [txt, limit, path, ignore, fields] = @query.match(/([0-9]+ )?(([\w]+\/){0,2})(.+)/)

    limit = +(limit.trim()) if limit

    pathParts = path.split("/").filter((p) -> p)

    if pathParts.length != 2
      @reply("You've got to specify the model and explore!")
      return

    fullyQualified = fields.split(",").map((f) -> f.trim()).map((f) ->
      if f.indexOf(".") == -1
        "#{pathParts[1]}.#{f}"
      else
        f
    )

    fields = []
    filters = {}
    sorts = []

    for field in fullyQualified
      matches = field.match(/([A-Za-z._]+)(\[(.+)\])? ?(asc|desc)?/i)
      [__, field, __, filter, sort] = matches
      if filter
        filters[field] = _.unescape filter
      if sort
        sorts.push "#{field} #{sort}"
      fields.push field

    queryDef =
      model: pathParts[0]
      view: pathParts[1]
      fields: fields
      filters: filters
      sorts: sorts
      limit: limit

    if @visualization
      queryDef.vis_config =
        type: "looker_column"

    error = (response) =>
      if response.error
        @reply(":warning: #{response.error}")
      else if response.message
        @reply(":warning: #{response.message}")
      else
        @reply("Something unexpected went wrong: #{JSON.stringify(response)}")
    @looker.client.post("queries", queryDef, (query) =>
      if @visualization
        @looker.client.get("queries/#{query.id}/run/png", (result) =>
          @postImage(query, result)
        , error, {encoding: null})
      else
        @looker.client.get("queries/#{query.id}/run/unified", (result) =>
          @postResult(query, result)
        , error)
    , error)

  postImage: (query, imageData) ->
    success = (url) =>
      @reply(
        attachments: [
          image_url: url
          text: query.share_url
        ]
      )
    error = (error) =>
      @reply(":warning: #{error}")
    @looker.storeBlob(imageData, success, error)

  postResult: (query, result) ->
    if result.data.length == 0
      @reply("#{query.share_url}\nNo results.")
    else if result.fields.dimensions.length == 0
      @reply(
        attachments: [
          fields: result.fields.measures.map((m) ->
            {title: m.label, value: result.data[0][m.name].rendered, short: true}
          )
          text: query.share_url
        ]
      )
    else if result.fields.dimensions.length == 1 && result.fields.measures.length == 0
      @reply(
        attachments: [
          fields: [
            title: result.fields.dimensions[0].label
            value: result.data.map((d) ->
              d[result.fields.dimensions[0].name].rendered
            ).join("\n")
          ]
          text: query.share_url
        ]
      )
    else if result.fields.dimensions.length == 1 && result.fields.measures.length == 1
      dim = result.fields.dimensions[0]
      mes = result.fields.measures[0]
      @reply(
        attachments: [
          fields: [
            title: "#{dim.label} – #{mes.label}"
            value: result.data.map((d) ->
              "#{d[dim.name].rendered} – #{d[mes.name].rendered}"
            ).join("\n")
          ]
          text: query.share_url
        ]
      )
    else
      @reply(query.share_url)

