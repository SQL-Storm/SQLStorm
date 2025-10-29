WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      p.OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Posts p
      ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.UserId IS NOT NULL
      AND p.OwnerUserId IS NOT NULL
      AND ph.UserId <> p.OwnerUserId
  ),
  UserContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  LatestEditDetails AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS LastEditorUserId,
      rpe.CreationDate AS LastEditDate,
      u.DisplayName AS LastEditorDisplayName
    FROM RankedPostEdits rpe
    JOIN Users u
      ON rpe.UserId = u.Id
    WHERE
      rpe.rn = 1
  )
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostTypeName,
  u_owner.DisplayName AS OwnerDisplayName,
  u_owner.Reputation AS OwnerReputation,
  p.CreationDate AS PostCreationDate,
  p.Score AS PostScore,
  p.ViewCount AS PostViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsCommunityOwned,
  CASE WHEN p.Tags IS NOT NULL THEN (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1) ELSE 0 END AS TagCount,
  COALESCE(led.LastEditorDisplayName, 'N/A') AS LastEditorDisplayName,
  COALESCE(led.LastEditDate, p.CreationDate) AS LastActivityDate,
  uc.TotalPostsOwned AS OwnerTotalPosts,
  uc.QuestionCount AS OwnerTotalQuestions,
  uc.AnswerCount AS OwnerTotalAnswers,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = p.Id AND c.UserId = p.OwnerUserId
  ) AS OwnerCommentCount,
  (
    SELECT
      MAX(ph.CreationDate)
    FROM PostHistory ph
    WHERE
      ph.PostId = p.Id AND ph.PostHistoryTypeId = 19
  ) AS LastProtectedDate,
  COALESCE(
    (
      SELECT
        STRING_AGG(lt.Name, ', ')
      FROM PostLinks pl
      JOIN LinkTypes lt
        ON pl.LinkTypeId = lt.Id
      WHERE
        pl.PostId = p.Id AND lt.Name = 'Duplicate'
    ),
    'None'
  ) AS DuplicateLinks
FROM Posts p
JOIN PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users u_owner
  ON p.OwnerUserId = u_owner.Id
LEFT JOIN LatestEditDetails led
  ON p.Id = led.PostId
LEFT JOIN UserContribution uc
  ON p.OwnerUserId = uc.OwnerUserId
WHERE
  p.PostTypeId IN (1, 2)
  AND p.OwnerUserId IS NOT NULL
  AND p.ClosedDate IS NULL
  AND (
    p.Title LIKE '%SQL%' OR p.Body LIKE '%SQL%' OR p.Tags LIKE '%<sql>%'
  )
  AND EXISTS (
    SELECT 1
    FROM Comments c
    WHERE
      c.PostId = p.Id AND c.Score > 5
  )
  AND (
    p.Score > 10 OR p.AnswerCount > 5
  )
GROUP BY
  p.Id,
  p.Title,
  pt.Name,
  u_owner.DisplayName,
  u_owner.Reputation,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  p.Tags,
  led.LastEditorDisplayName,
  led.LastEditDate,
  uc.TotalPostsOwned,
  uc.QuestionCount,
  uc.AnswerCount,
  p.OwnerUserId
HAVING
  COUNT(DISTINCT p.Id) > 1
ORDER BY
  LastActivityDate DESC
LIMIT 100;