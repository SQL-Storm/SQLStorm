-- {"query": "5528.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 590} 
WITH TopQuestions AS (
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
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    -- window: rank by score by day
    ROW_NUMBER() OVER (
      PARTITION BY DATE(p.CreationDate)
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS DayRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.Tags IS NOT NULL
),
TagAggregates AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(t.Count) AS AvgTagUsage
  FROM Tags t
  CROSS APPLY (
    SELECT unnest(string_to_array(substr(t.TagName, 2, length(t.TagName)-2), '><')) AS TagName
  ) AS tg
  GROUP BY t.TagName
),
CommentStats AS (
  SELECT
    p.Id AS PostId,
    COUNT(c.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE v.VoteTypeId IN (2,3,16)
  GROUP BY p.Id
)
SELECT
  tq.PostId,
  tq.Title,
  tq.Tags,
  tq.CreationDate,
  tq.Score,
  tq.ViewCount,
  tq.OwnerDisplayName,
  tq.Reputation,
  tc.CommentCount,
  ra.LastVoteDate,
  ta.QuestionCount,
  ta.AvgTagUsage,
  -- computed fields
  (CASE WHEN tq.Score > 100 THEN 'Hot' ELSE 'Normal' END) AS Bucketing,
  (CASE WHEN tq.ViewCount > 10000 THEN TRUE ELSE FALSE END) AS HighView
FROM TopQuestions tq
LEFT JOIN CommentStats tc ON tc.PostId = tq.PostId
LEFT JOIN RecentActivity ra ON ra.PostId = tq.PostId
LEFT JOIN TagAggregates ta ON ta.TagName = ANY (regexp_split_to_array(tq.Tags, '<|>'))
WHERE
  tq.DayRank <= 5
ORDER BY tq.CreationDate DESC
LIMIT 200;