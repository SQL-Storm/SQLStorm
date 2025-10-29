-- {"query": "5021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 634} 
WITH
-- sample generated dataset slices
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
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
TopTags AS (
  SELECT t.TagName,
         AVG(p.Score) AS AvgScore,
         SUM(p.ViewCount) AS TotalViews,
         COUNT(*) AS QCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN UNNEST(string_to_array(p.Tags, '><')) AS t(TagName) ON true
  GROUP BY t.TagName
  HAVING COUNT(*) > 5
),
UserStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.FavoriteCount, -- note: column may not exist in real schema; using existing closest: UpVotes/DownVotes/Views
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
  WHERE v.CreationDate >= NOW() - INTERVAL '14 days'
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
  LEFT JOIN ActivityWindow aw ON aw.PostId = rq.Id
  WHERE (ts.TagName IS NULL OR ts.TagName IN ('c#','sql','performance'))
    AND us.Reputation > 100
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
ORDER BY PostCreated DESC, TotalViews DESC
LIMIT 100;