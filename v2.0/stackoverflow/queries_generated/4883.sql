-- {"query": "4883.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1245} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS NumPosts,
      SUM(p.ViewCount) AS TotalViews,
      SUM(p.AnswerCount) AS TotalAnswers,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LatestPostDate,
      CASE
        WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Prolific'
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Active'
        ELSE 'Regular'
      END AS ActivityLevel
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  FrequentEditors AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS EditedPostCount,
      MAX(rpe.CreationDate) AS LatestEditDate
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
    HAVING
      COUNT(DISTINCT rpe.PostId) > 50
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      upa.NumPosts,
      upa.TotalViews,
      upa.TotalAnswers,
      upa.AvgScore,
      upa.ActivityLevel,
      COALESCE(fe.EditedPostCount, 0) AS EditedPostCount,
      COALESCE(fe.LatestEditDate, u.CreationDate) AS LastMeaningfulActivityDate,
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM Badges AS b
          WHERE
            b.UserId = u.Id AND b.Name LIKE '%Expert%'
        ) THEN TRUE
        ELSE FALSE
      END AS HasExpertBadge
    FROM Users AS u
    LEFT JOIN UserPostActivity AS upa
      ON u.Id = upa.OwnerUserId
    LEFT JOIN FrequentEditors AS fe
      ON u.Id = fe.UserId
    WHERE
      u.Id > 0 /* Exclude community user */
  )
SELECT
  ue.UserId,
  ue.DisplayName,
  ue.Reputation,
  ue.ActivityLevel,
  ue.HasExpertBadge,
  ue.EditedPostCount,
  ue.LastMeaningfulActivityDate,
  p.Title,
  p.Tags,
  p.CommunityOwnedDate,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    WHEN p.OwnerUserId = -1 THEN 'Unknown Owner'
    ELSE 'Active'
  END AS PostStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND LENGTH(c.Text) > 50
  ) AS LongCommentCount,
  SUBSTRING(p.Body, 1, 200) AS BodyPreview,
  p.FavoriteCount,
  CASE
    WHEN p.AnswerCount > 0 AND p.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer Exists'
    WHEN p.AnswerCount > 0 THEN 'Answers Exist'
    ELSE 'No Answers'
  END AS AnswerStatus,
  ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostSequenceWithinType
FROM Posts AS p
JOIN UserEngagement AS ue
  ON p.OwnerUserId = ue.UserId
LEFT JOIN PostLinks AS pl
  ON p.Id = pl.PostId
WHERE
  p.PostTypeId IN (1, 2) /* Questions and Answers */
  AND p.CreationDate >= '2023-01-01'
  AND ue.Reputation > 10000
  AND (
    pl.LinkTypeId = 3 /* Duplicate links */
    OR p.FavoriteCount > 50
    OR ue.EditedPostCount > 100
  )
  AND ue.DisplayName NOT LIKE '%Admin%'
GROUP BY
  p.Id,
  ue.UserId,
  ue.DisplayName,
  ue.Reputation,
  ue.ActivityLevel,
  ue.HasExpertBadge,
  ue.EditedPostCount,
  ue.LastMeaningfulActivityDate,
  p.Title,
  p.Tags,
  p.CommunityOwnedDate,
  p.ClosedDate,
  p.OwnerUserId,
  p.Body,
  p.FavoriteCount,
  p.AnswerCount,
  p.AcceptedAnswerId
HAVING
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 0 OR SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 0;
