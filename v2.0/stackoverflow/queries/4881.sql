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
  UserActivitySummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS TotalQuestions,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      MAX(u.Reputation) AS MaxReputation,
      AVG(p.Score) AS AveragePostScore,
      CAST(SUM(CASE WHEN EXTRACT(YEAR FROM p.CreationDate) = 2023 THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(DISTINCT p.Id),0) AS ProportionOf2023Posts
    FROM
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName
    HAVING
      COUNT(DISTINCT p.Id) > 10
  )
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostType,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  COALESCE(p.CommentCount, 0) AS CommentCount,
  COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
  uas.TotalQuestions AS UserTotalQuestions,
  uas.TotalAnswers AS UserTotalAnswers,
  uas.MaxReputation AS UserMaxReputation,
  uas.AveragePostScore AS UserAvgPostScore,
  uas.ProportionOf2023Posts AS UserProportion2023Posts,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  (
    SELECT COUNT(*)
    FROM Comments c
    WHERE c.PostId = p.Id AND c.Score > 5
  ) AS HighScoringCommentCount,
  (
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = p.Id AND v.VoteTypeId = 2
  ) AS TotalUpvotes,
  rpe.UserId AS LastEditorUserId,
  rpe.CreationDate AS LastEditDate,
  CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS INTEGER) AS DaysSinceLastActivity,
  LENGTH(p.Body) AS BodyLength,
  UPPER(SUBSTR(p.Title, 1, 3)) AS TitlePrefix
FROM
  Posts p
  JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  LEFT JOIN UserActivitySummary uas
    ON u.Id = uas.UserId
  LEFT JOIN RankedPostEdits rpe
    ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE
  p.Score > 10
  AND p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND (
    uas.MaxReputation IS NULL OR uas.MaxReputation < 10000
  )
  AND pt.Name = 'Question'
UNION
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostType,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  COALESCE(p.CommentCount, 0) AS CommentCount,
  COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
  uas.TotalQuestions AS UserTotalQuestions,
  uas.TotalAnswers AS UserTotalAnswers,
  uas.MaxReputation AS UserMaxReputation,
  uas.AveragePostScore AS UserAvgPostScore,
  uas.ProportionOf2023Posts AS UserProportion2023Posts,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  (
    SELECT COUNT(*)
    FROM Comments c
    WHERE c.PostId = p.Id AND c.Score > 5
  ) AS HighScoringCommentCount,
  (
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = p.Id AND v.VoteTypeId = 2
  ) AS TotalUpvotes,
  rpe.UserId AS LastEditorUserId,
  rpe.CreationDate AS LastEditDate,
  CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS INTEGER) AS DaysSinceLastActivity,
  LENGTH(p.Body) AS BodyLength,
  UPPER(SUBSTR(p.Title, 1, 3)) AS TitlePrefix
FROM
  Posts p
  JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  LEFT JOIN UserActivitySummary uas
    ON u.Id = uas.UserId
  LEFT JOIN RankedPostEdits rpe
    ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE
  p.Score < -5
  AND pt.Name = 'Answer'
  AND u.DownVotes > 100
  AND EXISTS (
    SELECT 1
    FROM Comments c
    WHERE c.PostId = p.Id AND c.Text LIKE '%performance%'
  );