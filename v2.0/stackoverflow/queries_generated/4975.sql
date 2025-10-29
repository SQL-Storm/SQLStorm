-- {"query": "4975.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 952} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserReputation AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      COUNT(b.Id) AS BadgeCount,
      MAX(b.Date) AS LastBadgeDate
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.Reputation
  ),
  PostEditSummary AS (
    SELECT
      rpe.PostId,
      COUNT(rpe.PostId) AS EditCount,
      MAX(rpe.CreationDate) AS LastEditDate
    FROM RankedPostEdits AS rpe
    GROUP BY
      rpe.PostId
  ),
  CommunityActivity AS (
    SELECT
      p.Id AS PostId,
      COUNT(CASE WHEN c.CreationDate >= DATE('now', '-30 day') THEN c.Id ELSE NULL END) AS RecentCommentCount,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentScoreSum
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    GROUP BY
      p.Id
  )
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
  ur.Reputation AS OwnerReputation,
  COALESCE(ur.BadgeCount, 0) AS OwnerBadgeCount,
  pes.EditCount AS TotalEdits,
  pes.LastEditDate,
  ca.RecentCommentCount,
  ca.PositiveCommentScoreSum,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  COALESCE(p.CommentCount, 0) AS CommentCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN p.Score > 1000 THEN 'HighScore'
    WHEN p.Score < 0 THEN 'LowScore'
    ELSE 'MediumScore'
  END AS ScoreCategory,
  LENGTH(p.Body) AS BodyLength,
  SUBSTRING(p.Tags, 2, INSTR(p.Tags, '>') - 2) AS PrimaryTag,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) THEN 'HasDuplicateLink'
    ELSE 'NoDuplicateLink'
  END AS LinkStatus,
  CASE
    WHEN ur.LastBadgeDate IS NULL THEN 'NeverReceivedBadge'
    WHEN ur.LastBadgeDate < DATE('now', '-365 day') THEN 'OldestBadge'
    ELSE 'RecentBadge'
  END AS BadgeRecency
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN UserReputation AS ur
  ON p.OwnerUserId = ur.UserId
LEFT JOIN PostEditSummary AS pes
  ON p.Id = pes.PostId
LEFT JOIN CommunityActivity AS ca
  ON p.Id = ca.PostId
WHERE
  p.CreationDate >= DATE('now', '-365 day') AND p.PostTypeId IN (1, 2) -- Questions and Answers
  AND (
    p.Score > 10 OR p.CommentCount > 5 OR ca.RecentCommentCount > 2
  )
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;
