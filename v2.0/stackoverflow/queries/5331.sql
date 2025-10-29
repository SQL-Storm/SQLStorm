WITH
  recent_scored_questions AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.ViewCount,
      p.Score,
      p.CreationDate,
      p.OwnerUserId,
      p.Tags,
      p.LastActivityDate,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ContentLicense
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
  ),
  top_tags AS (
    SELECT
      unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
      p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  tag_popularity AS (
    SELECT
      TagName,
      COUNT(*) AS TagCount,
      AVG(p.Score) AS AvgScore,
      SUM(p.ViewCount) AS TotalViews
    FROM top_tags t
    JOIN Posts p ON p.Id = t.PostId
    GROUP BY TagName
  ),
  author_stats AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate,
      u.DisplayName,
      u.UpVotes,
      u.DownVotes,
      u.Views,
      u.Location,
      u.AboutMe,
      u.WebsiteUrl
    FROM Users u
  ),
  joined AS (
    SELECT
      q.PostId,
      q.Title,
      q.ViewCount,
      q.Score,
      q.CreationDate,
      q.LastActivityDate,
      q.AnswerCount,
      q.CommentCount,
      a.UserId AS AuthorId,
      a.DisplayName AS AuthorName,
      tt.TagName,
      ts.TagCount,
      ts.AvgScore AS TagAvgScore,
      ts.TotalViews AS TagTotalViews
    FROM recent_scored_questions q
    LEFT JOIN Votes v ON v.PostId = q.PostId AND v.VoteTypeId = 2
    LEFT JOIN author_stats a ON a.UserId = q.OwnerUserId
    LEFT JOIN top_tags tt ON tt.PostId = q.PostId
    LEFT JOIN tag_popularity ts ON ts.TagName = tt.TagName
    WHERE (q.ViewCount > 0 OR q.Score > 0)
      AND (q.AnswerCount IS NULL OR q.AnswerCount >= 0)
  ),
  correlated AS (
    SELECT
      b1.PostId,
      b1.Title,
      b1.ViewCount,
      b1.Score,
      b1.CreationDate,
      b1.LastActivityDate,
      b1.AnswerCount,
      b1.CommentCount,
      b1.AuthorId,
      b1.AuthorName,
      b1.TagName,
      b1.TagCount,
      b1.TagAvgScore,
      b1.TagTotalViews
    FROM joined b1
    ORDER BY b1.LastActivityDate DESC
    LIMIT 200
  ),
  windowed AS (
    SELECT
      c.PostId,
      c.Title,
      c.ViewCount,
      c.Score,
      c.CreationDate,
      c.LastActivityDate,
      c.AnswerCount,
      c.CommentCount,
      c.AuthorId,
      c.AuthorName,
      c.TagName,
      c.TagCount,
      c.TagAvgScore,
      c.TagTotalViews,
      ROW_NUMBER() OVER (PARTITION BY c.AuthorId ORDER BY c.LastActivityDate DESC) AS rn
    FROM correlated c
  )
SELECT
  w.PostId,
  w.Title,
  w.AuthorName,
  w.AuthorId,
  w.TagName,
  w.TagCount,
  w.TagAvgScore,
  w.TagTotalViews,
  w.ViewCount,
  w.Score,
  w.CreationDate,
  w.LastActivityDate,
  w.AnswerCount,
  w.CommentCount
FROM windowed w
WHERE w.rn = 1
  AND w.TagName IS NOT NULL
ORDER BY w.LastActivityDate DESC, w.Score DESC
LIMIT 50;