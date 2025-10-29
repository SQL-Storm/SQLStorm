-- {"query": "4667.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1112}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
      ) AS UpVoteCount,
      (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
      ) AS DownVoteCount,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      p.OwnerUserId
    FROM
      Posts p
    WHERE
      p.PostTypeId = 1
  )
SELECT
  ua.DisplayName AS UserDisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.TotalPosts,
  ua.QuestionCount,
  ua.AnswerCount AS UserAnswerCount,
  pe.Title AS PostTitle,
  pe.Score AS PostScore,
  pe.CommentCount AS PostCommentCount,
  pe.FavoriteCount AS PostFavoriteCount,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.IsClosed,
  CASE WHEN rpe.PostId IS NOT NULL THEN 'Edited' ELSE 'Not Edited' END AS EditStatus,
  CAST((EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ua.LastPostActivityDate)) / 86400) AS INTEGER) AS DaysSinceLastActivity,
  CASE
    WHEN ua.Reputation > 100000 THEN 'High Reputation'
    WHEN ua.Reputation > 10000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationCategory,
  CASE
    WHEN pe.Score > 50 THEN 'High Score'
    WHEN pe.Score > 10 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  (
    SELECT AVG(p_inner.Score)
    FROM Posts p_inner
    WHERE p_inner.OwnerUserId = ua.UserId
  ) AS AvgUserPostScore,
  (
    SELECT CASE WHEN COUNT(b.Id) > 0 THEN 1 ELSE 0 END
    FROM Badges b
    WHERE b.UserId = ua.UserId AND b.Class = 1
  ) AS HasGoldBadge,
  (ua.DisplayName || ' (' || ua.Reputation || ')') AS DisplayNameWithReputation
FROM
  UserActivity ua
  LEFT JOIN PostEngagement pe
    ON ua.UserId = pe.OwnerUserId
  LEFT JOIN RankedPostEdits rpe
    ON pe.PostId = rpe.PostId AND rpe.rn = 1
WHERE
  ua.TotalPosts > 5
  AND ua.Reputation > 100
  AND pe.Score > 0
  AND pe.IsClosed = 0
  AND ua.DisplayName IS NOT NULL
  AND ua.DisplayName <> ''
  AND ua.LastPostActivityDate BETWEEN (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year') AND TIMESTAMP '2024-10-01 12:34:56'
ORDER BY
  ua.Reputation DESC,
  pe.Score DESC;