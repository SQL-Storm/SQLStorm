-- {"query": "5296.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 810} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn_by_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ViewCount > 50
    AND p.Score > 0
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.OwnerUserId,
    ROW_NUMBER() OVER (
      ORDER BY p.LastActivityDate DESC, p.Score DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > NOW() - INTERVAL '30 days'
),
tag_aggregation AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.Score) AS MaxScore
  FROM Tags tg
  JOIN Posts p ON tg.ExcerptPostId = p.Id
  JOIN (SELECT TagName FROM Tags) t ON tg.TagName = t.TagName
  GROUP BY t.TagName
),
outer_join_example AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerName,
    r.Reputation,
    lc.Name AS LastEditorRole, -- from hypothetical last editor role
    a.LastActivityDate,
    a.Score AS ActivityScore,
    COALESCE(u2.Reputation, 0) AS LastEditorReputation
  FROM ranked_posts r
  LEFT JOIN Posts a ON a.Id = r.PostId
  LEFT JOIN Users u2 ON a.LastEditorUserId = u2.Id
  LEFT JOIN PostHistory ph ON ph.PostId = r.PostId
  LEFT JOIN PostHistoryTypes lc ON ph.PostHistoryTypeId = lc.Id
  WHERE r.rn_by_owner <= 3
),
correlated_subquery AS (
  SELECT
    p.Id,
    p.Title,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountForPost,
    (SELECT MAX(CASE WHEN v.VoteTypeId = 2 THEN v.CreationDate END)
     FROM Votes v WHERE v.PostId = p.Id) AS LastUpVoteDate
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  oje.PostId,
  oje.Title,
  oje.OwnerName,
  oje.Reputation AS OwnerReputation,
  oje.LastEditorRole,
  oje.LastActivityDate,
  oje.ActivityScore,
  oje.LastEditorReputation,
  ca.CommentCountForPost,
  ca.LastUpVoteDate,
  ta.TagName,
  ta.PostCount AS TagPostCount,
  ta.AvgScore AS TagAvgScore,
  ta.MaxScore AS TagMaxScore
FROM outer_join_example oje
JOIN correlated_subquery cs ON cs.Id = oje.PostId
LEFT JOIN tag_aggregation ta
  ON ta.TagName = ANY(string_to_array(p.Title || ' ' || p.Tags, '><')) -- approximate tag extraction
ORDER BY oje.LastActivityDate DESC
LIMIT 100;