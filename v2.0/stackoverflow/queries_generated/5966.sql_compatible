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
   AND v.VoteTypeId = 2
  WHERE p.PostTypeId = 1
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
    -- aggregate string of history types per post
    STRING_AGG(CONCAT('c', th.Id, ':', th.Name), '|' ORDER BY th.Id) AS HistorySummary,
    -- Window function over recent activity
    ROW_NUMBER() OVER (ORDER BY f.LastVoteDate DESC) AS RecencyRank
  FROM flagged_questions f
  LEFT JOIN PostHistory ph
    ON ph.PostId = f.PostId
  LEFT JOIN PostHistoryTypes th
    ON ph.PostHistoryTypeId = th.Id
  GROUP BY
    f.PostId,
    f.Title,
    f.CreationDate,
    f.OwnerDisplayName,
    f.Score,
    f.ViewCount,
    f.Tags,
    f.LastVoteDate
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