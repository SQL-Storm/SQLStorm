-- {"query": "4862.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1453}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
      JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      (
        SELECT
          COUNT(*)
        FROM
          Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadgeCount
    FROM
      Users AS u
    WHERE
      u.Reputation > 50000
  )
SELECT
  p.Id AS PostId,
  p.Title,
  p.CreationDate AS PostCreationDate,
  COALESCE(hr.DisplayName, 'Unknown User') AS PostOwnerDisplayName,
  hr.Reputation AS PostOwnerReputation,
  hr.GoldBadgeCount AS PostOwnerGoldBadges,
  upc.QuestionCount AS OwnerQuestionCount,
  upc.AnswerCount AS OwnerAnswerCount,
  rpe.EditDate AS LastEditDate,
  rpe.EditType AS LastEditType,
  (
    SELECT
      COUNT(*)
    FROM
      Comments AS c
    WHERE
      c.PostId = p.Id AND c.Score > 5
  ) AS HighScoreCommentCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN p.FavoriteCount > 100 THEN 'Very Popular'
    WHEN p.FavoriteCount > 50 THEN 'Popular'
    ELSE 'Standard'
  END AS FavoriteStatus,
  UPPER(SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))) AS PrimaryTag,
  (
    SELECT
      AVG(CAST(v.VoteTypeId AS DOUBLE PRECISION))
    FROM
      Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
  ) AS AverageVoteType,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus
FROM
  Posts AS p
  LEFT JOIN HighReputationUsers AS hr ON p.OwnerUserId = hr.Id
  LEFT JOIN UserPostCounts AS upc ON p.OwnerUserId = upc.OwnerUserId
  LEFT JOIN RankedPostEdits AS rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE
  p.PostTypeId = 1
  AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND p.OwnerUserId IS NOT NULL
  AND (
    hr.Reputation IS NULL OR hr.Reputation > 10000
  )
  AND p.ViewCount > 1000
UNION ALL
SELECT
  p.Id AS PostId,
  p.Title,
  p.CreationDate AS PostCreationDate,
  COALESCE(hr.DisplayName, 'Unknown User') AS PostOwnerDisplayName,
  hr.Reputation AS PostOwnerReputation,
  hr.GoldBadgeCount AS PostOwnerGoldBadges,
  upc.QuestionCount AS OwnerQuestionCount,
  upc.AnswerCount AS OwnerAnswerCount,
  rpe.EditDate AS LastEditDate,
  rpe.EditType AS LastEditType,
  (
    SELECT
      COUNT(*)
    FROM
      Comments AS c
    WHERE
      c.PostId = p.Id AND c.Score > 2
  ) AS HighScoreCommentCount,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN p.FavoriteCount > 50 THEN 'Popular'
    ELSE 'Standard'
  END AS FavoriteStatus,
  NULL AS PrimaryTag,
  (
    SELECT
      AVG(CAST(v.VoteTypeId AS DOUBLE PRECISION))
    FROM
      Votes AS v
    WHERE
      v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
  ) AS AverageVoteType,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1
    ) THEN 'Is Linked To'
    ELSE 'Not Linked To'
  END AS DuplicateLinkStatus
FROM
  Posts AS p
  LEFT JOIN HighReputationUsers AS hr ON p.OwnerUserId = hr.Id
  LEFT JOIN UserPostCounts AS upc ON p.OwnerUserId = upc.OwnerUserId
  LEFT JOIN RankedPostEdits AS rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE
  p.PostTypeId = 2
  AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND p.OwnerUserId IS NOT NULL
  AND p.Score > 10
ORDER BY
  PostCreationDate DESC;