-- {"query": "4693.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1340} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.UserDisplayName,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
      JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM
      Users AS u
      LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
      LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      (
        SELECT
          COUNT(*)
        FROM
          Comments AS c
        WHERE
          c.PostId = p.Id
      ) AS TotalComments,
      (
        SELECT
          COUNT(*)
        FROM
          Votes AS v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 2 -- UpVotes
      ) AS TotalUpVotes,
      (
        SELECT
          COUNT(*)
        FROM
          Votes AS v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 3 -- DownVotes
      ) AS TotalDownVotes,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END AS PostStatus
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 1 -- Questions only
  )
SELECT
  pe.Title,
  pe.PostStatus,
  pe.Score,
  pe.TotalUpVotes,
  pe.TotalDownVotes,
  pe.TotalComments,
  pe.FavoriteCount,
  uc.DisplayName AS OwnerDisplayName,
  uc.QuestionCount,
  uc.AnswerCount,
  uc.GoldBadgeCount,
  uc.SilverBadgeCount,
  uc.BronzeBadgeCount,
  rpe.EditType AS LatestEditType,
  rpe.EditDate AS LatestEditDate,
  COALESCE(u.DisplayName, 'Anonymous') AS LastEditorDisplayName,
  CASE
    WHEN pe.Score > 100 THEN 'High Score'
    WHEN pe.Score BETWEEN 50 AND 100 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  CAST(pe.CreationDate AS DATE) AS PostCreationDate,
  DATEDIFF(
    DAY,
    pe.CreationDate,
    pe.LastActivityDate
  ) AS DaysSinceLastActivity
FROM
  PostEngagement AS pe
  JOIN UserContribution AS uc ON pe.OwnerUserId = uc.UserId
  LEFT JOIN RankedPostEdits AS rpe ON pe.PostId = rpe.PostId AND rpe.rn = 1
  LEFT JOIN Users AS u ON pe.LastEditorUserId = u.Id
WHERE
  pe.TotalUpVotes > pe.TotalDownVotes * 2
  AND pe.FavoriteCount > 5
  AND uc.GoldBadgeCount > 0
  AND pe.PostStatus = 'Open'
  AND pe.OwnerUserId IS NOT NULL
UNION ALL
SELECT
  pe.Title,
  pe.PostStatus,
  pe.Score,
  pe.TotalUpVotes,
  pe.TotalDownVotes,
  pe.TotalComments,
  pe.FavoriteCount,
  uc.DisplayName AS OwnerDisplayName,
  uc.QuestionCount,
  uc.AnswerCount,
  uc.GoldBadgeCount,
  uc.SilverBadgeCount,
  uc.BronzeBadgeCount,
  rpe.EditType AS LatestEditType,
  rpe.EditDate AS LatestEditDate,
  COALESCE(u.DisplayName, 'Anonymous') AS LastEditorDisplayName,
  CASE
    WHEN pe.Score > 100 THEN 'High Score'
    WHEN pe.Score BETWEEN 50 AND 100 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  CAST(pe.CreationDate AS DATE) AS PostCreationDate,
  DATEDIFF(
    DAY,
    pe.CreationDate,
    pe.LastActivityDate
  ) AS DaysSinceLastActivity
FROM
  PostEngagement AS pe
  JOIN UserContribution AS uc ON pe.OwnerUserId = uc.UserId
  LEFT JOIN RankedPostEdits AS rpe ON pe.PostId = rpe.PostId AND rpe.rn = 1
  LEFT JOIN Users AS u ON pe.LastEditorUserId = u.Id
WHERE
  pe.PostStatus = 'Closed'
  AND pe.CommentCount > 10
  AND DATEDIFF(
    DAY,
    pe.CreationDate,
    pe.ClosedDate
  ) < 30;
