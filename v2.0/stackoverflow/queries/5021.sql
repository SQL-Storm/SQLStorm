-- {"query": "5021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 634}
WITH
RecentQuestions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.CreationDate,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60' DAY
),
TopTags AS (
  SELECT t.TagName,
         AVG(p.Score) AS AvgScore,
         SUM(p.ViewCount) AS TotalViews,
         COUNT(*) AS QCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  -- split tags like '<tag1><tag2>' into elements; remove empty elements
  CROSS JOIN LATERAL (
    SELECT TRIM(BOTH '<>' FROM s.Tag) AS TagName
    FROM UNNEST(string_to_array(p.Tags, '><')) AS s(Tag)
  ) t
  GROUP BY t.TagName
  HAVING COUNT(*) > 5
),
UserStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         -- FavoriteCount may not exist; choose NULL if absent
         CAST(NULL AS BIGINT) AS FavoriteCount,
         u.UpVotes,
         u.Views,
         u.LastAccessDate
  FROM Users u
),
ActivityWindow AS (
  SELECT v.PostId,
         v.UserId,
         v.VoteTypeId,
         v.CreationDate,
         ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14' DAY
),
Combined AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate AS PostCreated,
    rq.OwnerUserId,
    rq.Score,
    rq.ViewCount,
    rq.Tags,
    rq.LastActivityDate,
    ts.TagName,
    ts.AvgScore,
    ts.TotalViews,
    ts.QCount,
    us.UserId,
    us.DisplayName,
    us.Reputation,
    aw.VoteTypeId,
    aw.CreationDate AS VoteDate,
    aw.rn
  FROM RecentQuestions rq
  LEFT JOIN TopTags ts ON true
  LEFT JOIN UserStats us ON rq.OwnerUserId = us.UserId
  LEFT JOIN ActivityWindow aw ON aw.PostId = rq.PostId
  WHERE (ts.TagName IS NULL OR ts.TagName IN ('c#','sql','performance'))
    AND (us.Reputation IS NULL OR us.Reputation > 100)
)
SELECT
  PostId,
  Title,
  PostCreated,
  OwnerUserId,
  DisplayName AS OwnerDisplayName,
  Reputation AS OwnerReputation,
  Score,
  ViewCount,
  Tags,
  LastActivityDate,
  TagName,
  AvgScore,
  TotalViews,
  QCount,
  VoteDate,
  CASE
    WHEN rn = 1 THEN 'Most recent vote'
    ELSE 'Older vote'
  END AS VoteRecency
FROM Combined
GROUP BY
  PostId,
  Title,
  PostCreated,
  OwnerUserId,
  DisplayName,
  Reputation,
  Score,
  ViewCount,
  Tags,
  LastActivityDate,
  TagName,
  AvgScore,
  TotalViews,
  QCount,
  VoteDate,
  rn
ORDER BY PostCreated DESC, TotalViews DESC
LIMIT 100;