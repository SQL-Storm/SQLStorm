-- {"query": "5607.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 968}
WITH
  recent_questions AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      p.LastActivityDate,
      p.CommentCount,
      p.AnswerCount,
      p.FavoriteCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
  ),
  tag_popularity AS (
    SELECT
      unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
      p.Id AS PostId,
      p.Score AS PostScore,
      p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  tag_stats AS (
    SELECT
      ts.TagName,
      COUNT(*) AS PostCount,
      AVG(ts.PostScore) AS AvgPostScore,
      SUM(ts.ViewCount) AS TotalViews
    FROM tag_popularity ts
    GROUP BY ts.TagName
  ),
  top_tags AS (
    SELECT
      ts.TagName,
      ts.PostCount,
      ts.AvgPostScore,
      ts.TotalViews,
      ROW_NUMBER() OVER (ORDER BY ts.TotalViews DESC, ts.AvgPostScore DESC, ts.PostCount DESC) AS rn
    FROM tag_stats ts
  ),
  enriched AS (
    SELECT
      rq.PostId,
      rq.Title,
      rq.CreationDate,
      rq.ViewCount,
      rq.Score,
      rq.OwnerUserId,
      rq.LastActivityDate,
      rq.CommentCount,
      rq.AnswerCount,
      rq.FavoriteCount,
      ARRAY_AGG(th.Name) AS HistoryTypes
    FROM recent_questions rq
    LEFT JOIN PostHistory ph ON ph.PostId = rq.PostId
    LEFT JOIN PostHistoryTypes th ON th.Id = ph.PostHistoryTypeId
    GROUP BY
      rq.PostId, rq.Title, rq.CreationDate, rq.ViewCount, rq.Score,
      rq.OwnerUserId, rq.LastActivityDate, rq.CommentCount, rq.AnswerCount, rq.FavoriteCount
  ),
  user_metrics AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate,
      u.Views,
      u.UpVotes,
      u.DownVotes,
      u.Location,
      u.WebsiteUrl,
      u.AboutMe,
      COUNT(DISTINCT b.Id) AS BadgesCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY
      u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
      u.Views, u.UpVotes, u.DownVotes, u.Location, u.WebsiteUrl, u.AboutMe
  ),
  relevant AS (
    SELECT
      e.PostId,
      e.Title,
      e.CreationDate,
      e.ViewCount,
      e.Score,
      e.OwnerUserId,
      e.LastActivityDate,
      e.CommentCount,
      e.AnswerCount,
      e.FavoriteCount,
      um.DisplayName AS OwnerDisplayName,
      array_length(e.HistoryTypes, 1) AS HistoryTypeCount
    FROM enriched e
    LEFT JOIN Users um ON um.Id = e.OwnerUserId
  ),
  final AS (
    SELECT
      r.PostId,
      r.Title,
      r.CreationDate,
      r.ViewCount,
      r.Score,
      r.OwnerUserId,
      r.OwnerDisplayName,
      r.LastActivityDate,
      r.CommentCount,
      r.AnswerCount,
      r.FavoriteCount,
      r.HistoryTypeCount,
      uu.Reputation,
      uu.Location,
      uu.WebsiteUrl,
      tt.TagName,
      ts.PostCount,
      ts.AvgPostScore,
      ts.TotalViews
    FROM relevant r
    LEFT JOIN user_metrics uu ON uu.UserId = r.OwnerUserId
    LEFT JOIN (
      SELECT
        t.TagName,
        t.PostCount,
        t.AvgPostScore,
        t.TotalViews
      FROM top_tags t
      WHERE t.rn <= 5
    ) tt ON 1 = 1
    LEFT JOIN tag_stats ts ON ts.TagName = tt.TagName
  )
SELECT
  *
FROM final
ORDER BY CreationDate DESC
LIMIT 100;