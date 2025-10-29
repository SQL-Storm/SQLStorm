-- {"query": "5966.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 554} 
WITH flagged_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerDisplayName,
    p.Score,
    p.ViewCount,
    p.Tags,
    COUNT(v.Id) AS VoteCount,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Votes v
    ON p.Id = v.PostId
   AND v.VoteTypeId = 2 -- UpMod
  WHERE p.PostTypeId = 1 -- Question
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.OwnerDisplayName, p.Score, p.ViewCount, p.Tags
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
complex_metrics AS (
  SELECT
    f.PostId,
    f.Title,
    f.CreationDate,
    f.OwnerDisplayName,
    f.Score AS OriginalScore,
    f.ViewCount,
    f.Tags,
    -- Nested correlated subquery with string aggregation
    (SELECT STRING_AGG(CONCAT('c', th.Id, ':', th.Name), '|')
       ORDER BY th.Id)
    AS HistorySummary,
    -- Window function over recent activity
    ROW_NUMBER() OVER (ORDER BY f.LastVoteDate DESC NULLS LAST) AS RecencyRank
  FROM flagged_questions f
  LEFT JOIN PostHistory ph
    ON ph.PostId = f.PostId
  LEFT JOIN PostHistoryTypes th
    ON ph.PostHistoryTypeId = th.Id
  WHERE ph.Id IS NULL OR ph.CreationDate = ph.CreationDate
)
SELECT
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.OriginalScore,
  cm.ViewCount,
  cm.Tags,
  cm.HistorySummary,
  cm.RecencyRank,
  au.Reputation,
  au.CreationDate AS UserCreationDate,
  au.LastAccessDate,
  au.Location,
  ai.LastActivityDate
FROM complex_metrics cm
JOIN Users au
  ON cm.OwnerDisplayName = au.DisplayName
LEFT JOIN recent_activity ai
  ON cm.PostId = ai.PostId
ORDER BY cm.RecencyRank
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;