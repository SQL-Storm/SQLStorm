-- {"query": "5855.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 926} 
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Created AS UserCreated
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TagExploded AS (
  SELECT
    ra.PostId,
    ra.Title,
    ts.TagName,
    ra.Reputation,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.CommentCount
  FROM RecentActivity ra
  CROSS APPLY (
    SELECT unnest(string_to_array(substr(Coalesce(ra.Tags, '[]'), 2, length(Coalesce(ra.Tags, '[]')) - 2), '><')) AS TagName
  ) AS ts
),
TopTags AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount,
    AVG(Score) AS AvgScore,
    SUM(ViewCount) AS TotalViews
  FROM TagExploded
  GROUP BY TagName
  ORDER BY PostCount DESC, AvgScore DESC
  LIMIT 10
),
ComplexJoins AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    v.VoteTypeId,
    vt.Name AS VoteTypeName,
    c.Id AS CommentId,
    c.Text AS CommentText,
    c.Score AS CommentScore,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    u.Reputation AS UserReputation,
    b.Id AS BadgeId,
    b.Name AS BadgeName,
    b.Class AS BadgeClass,
    b.Date AS BadgeDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Users u ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE p.LastActivityDate >= NOW() - INTERVAL '60 days'
),
WindowAgg AS (
  SELECT
    t.PostId,
    t.Title,
    t.Score,
    t.ViewCount,
    t.CommentCount,
    t.AnswerCount,
    t.FavoriteCount,
    t.VoteTypeName,
    t.CommentText,
    t.UserDisplayName,
    t.UserReputation,
    ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Score DESC, t.ViewCount DESC NULLS LAST) AS rn
  FROM (
    SELECT
      c.PostId,
      c.Title,
      p.Score,
      p.ViewCount,
      p.CommentCount,
      p.AnswerCount,
      p.FavoriteCount,
      vt.Name AS VoteTypeName,
      c.Text AS CommentText,
      u.DisplayName AS UserDisplayName,
      u.Reputation AS UserReputation,
      tg.TagName,
      tg.PostId AS TagPostId
    FROM ComplexJoins cj
    LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(substr(Coalesce(t.Tags, '[]'), 2, length(Coalesce(t.Tags, '[]')) - 2), '><')) AS TagName
    ) AS tg ON true
    LEFT JOIN Posts t ON t.Id = cj.PostId
    WHERE tg.TagName IS NOT NULL
  ) t
)
SELECT
  w.PostId,
  w.Title,
  w.Score,
  w.ViewCount,
  w.CommentCount,
  w.AnswerCount,
  w.FavoriteCount,
  w.VoteTypeName,
  w.CommentText,
  w.UserDisplayName,
  w.UserReputation,
  wt.PostId AS TagPostId,
  wt.TagName
FROM WindowAgg w
JOIN TopTags wt ON wt.PostCount > 0
WHERE w.rn = 1
ORDER BY wt.PostCount DESC, w.Score DESC
LIMIT 100;