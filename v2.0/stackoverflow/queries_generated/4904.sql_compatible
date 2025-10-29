WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      MAX(p.CreationDate) AS LatestPostDate
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  UserEditFrequency AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS DistinctEditedPosts,
      AVG(EXTRACT(EPOCH FROM (rpe.CreationDate - u.CreationDate)) / 86400.0) AS AvgDaysToFirstEdit
    FROM
      RankedPostEdits AS rpe
    JOIN
      Users AS u
      ON rpe.UserId = u.Id
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
  ),
  PostWithAcceptedAnswerDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      p.OwnerUserId AS QuestionOwnerUserId,
      p.AnswerCount,
      p.Score AS QuestionScore,
      aa.Id AS AcceptedAnswerId,
      aa.OwnerUserId AS AcceptedAnswerOwnerUserId,
      aa.CreationDate AS AcceptedAnswerCreationDate,
      aa.Score AS AcceptedAnswerScore,
      EXTRACT(EPOCH FROM (aa.CreationDate - p.CreationDate)) / 60.0 AS TimeToAcceptedAnswerMinutes,
      CASE
        WHEN p.OwnerUserId = aa.OwnerUserId THEN 1
        ELSE 0
      END AS IsOwnerAccepted,
      ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY aa.Score DESC, aa.CreationDate ASC) AS aa_rn
    FROM
      Posts AS p
    LEFT JOIN
      Posts AS aa
      ON p.Id = aa.ParentId
      AND aa.PostTypeId = 2
    WHERE
      p.PostTypeId = 1
      AND p.AcceptedAnswerId IS NOT NULL
  ),
  HighActivityUsers AS (
    SELECT
      upa.OwnerUserId
    FROM
      UserPostActivity AS upa
    WHERE
      upa.TotalPosts > 1000
      AND upa.TotalScore > 5000
  ),
  FrequentEditors AS (
    SELECT
      uef.UserId
    FROM
      UserEditFrequency AS uef
    WHERE
      uef.DistinctEditedPosts > 50
      AND uef.AvgDaysToFirstEdit < 30
  ),
  AggregatedPostData AS (
    SELECT
      p.Id,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      pt.Name AS PostTypeName,
      COALESCE(p.AnswerCount, 0) AS SafeAnswerCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      AVG(c.Score) OVER (PARTITION BY p.Id) AS AvgCommentScore
    FROM
      Posts AS p
    JOIN
      PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId IN (1, 2)
  )
SELECT
  ap.Id AS PostId,
  ap.Title AS PostTitle,
  ap.CreationDate AS PostCreationDate,
  ap.Score AS PostScore,
  ap.ViewCount AS PostViewCount,
  ap.PostTypeName,
  ap.PostStatus,
  ap.AvgCommentScore,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Badges AS b
      WHERE b.UserId = u.Id AND b.Name LIKE '%gold%' AND b.Class = 1
    ) THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS OwnerBadgeStatus,
  CASE WHEN upu.OwnerUserId IS NOT NULL THEN 'HighActivity' ELSE 'NormalActivity' END AS UserActivityLevel,
  CASE WHEN fed.UserId IS NOT NULL THEN 'FrequentEditor' ELSE 'InfrequentEditor' END AS UserEditLevel,
  COALESCE(paaad.TimeToAcceptedAnswerMinutes, -1) AS TimeToAcceptAnswer,
  paaad.IsOwnerAccepted,
  CASE
    WHEN ap.Title IS NOT NULL AND CHAR_LENGTH(ap.Title) > 10 THEN UPPER(SUBSTRING(ap.Title FROM 1 FOR 10)) || '...'
    WHEN ap.Title IS NOT NULL THEN UPPER(ap.Title)
    ELSE 'Untitled Post'
  END AS ProcessedTitle,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = ap.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory AS ph
    WHERE
      ph.PostId = ap.Id
      AND ph.PostHistoryTypeId = 10
      AND ph.Comment LIKE '%Exact Duplicate%'
  ) AS ExactDuplicateCloseCount
FROM
  AggregatedPostData AS ap
LEFT JOIN
  Users AS u
  ON ap.OwnerUserId = u.Id
LEFT JOIN
  HighActivityUsers AS upu
  ON ap.OwnerUserId = upu.OwnerUserId
LEFT JOIN
  FrequentEditors AS fed
  ON ap.OwnerUserId = fed.UserId
LEFT JOIN
  PostWithAcceptedAnswerDetails AS paaad
  ON ap.Id = paaad.QuestionId AND paaad.aa_rn = 1
WHERE
  ap.Score > 5
  OR ap.ViewCount > 1000
  OR (ap.PostStatus = 'Closed' AND ap.Score > 0)
ORDER BY
  ap.Score DESC,
  ap.ViewCount DESC;