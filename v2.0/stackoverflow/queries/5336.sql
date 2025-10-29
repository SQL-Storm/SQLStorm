-- {"query": "5336.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 834}
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
    p.ClosedDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.TagName IS NOT NULL
),
question_tag_scores AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.LastActivityDate,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    STRING_AGG(tt.TagName, ',') AS TagsList
  FROM recent_questions q
  LEFT JOIN LATERAL (
    SELECT trim(x) AS tagName
    FROM (
      SELECT regexp_split_to_table(q.Tags, '[<>]+') AS x
    ) s
    WHERE x <> ''
  ) tag_split ON TRUE
  LEFT JOIN Tags tt ON tt.TagName = tag_split.tagName
  GROUP BY
    q.PostId, q.Title, q.CreationDate, q.ViewCount, q.Score, q.OwnerUserId,
    q.LastActivityDate, q.AnswerCount, q.CommentCount, q.FavoriteCount
),
activity_window AS (
  SELECT
    q.PostId,
    q.Title,
    q.TagsList,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    q.OwnerUserId,
    ROW_NUMBER() OVER (
      PARTITION BY q.OwnerUserId
      ORDER BY q.LastActivityDate DESC
    ) AS rn_owner
  FROM question_tag_scores q
),
enhanced AS (
  SELECT
    aw.PostId,
    aw.Title,
    aw.TagsList,
    aw.CreationDate,
    aw.LastActivityDate,
    aw.ViewCount,
    aw.Score,
    aw.AnswerCount,
    aw.CommentCount,
    aw.FavoriteCount,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    aw.OwnerUserId,
    EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = aw.OwnerUserId
        AND b.Class = 1
        AND b.Date <= aw.LastActivityDate
    ) AS IsGoldBadgeOwner
  FROM activity_window aw
  LEFT JOIN Users u ON u.Id = aw.OwnerUserId
  WHERE aw.rn_owner = 1
)
SELECT
  e.PostId,
  e.Title,
  e.TagsList,
  e.CreationDate,
  e.LastActivityDate,
  e.ViewCount,
  e.Score,
  e.AnswerCount,
  e.CommentCount,
  e.FavoriteCount,
  e.OwnerDisplayName,
  e.OwnerReputation,
  e.Location,
  e.AccountId,
  e.IsGoldBadgeOwner,
  (SELECT COUNT(*) FROM Posts p2
   WHERE p2.PostTypeId = 1
     AND p2.OwnerUserId = e.OwnerUserId
     AND p2.LastActivityDate > e.LastActivityDate - INTERVAL '30 days') AS RecentActivityByAuthor,
  (SELECT AVG(v2.BountyAmount)
   FROM Votes v2
   WHERE v2.PostId = e.PostId
     AND v2.VoteTypeId = 8) AS AvgBountyStart
FROM enhanced e
ORDER BY e.LastActivityDate DESC
LIMIT 100;