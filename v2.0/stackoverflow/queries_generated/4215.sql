-- {"query": "4215.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1180} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      p.OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN Posts AS p
      ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL AND p.OwnerUserId IS NOT NULL AND ph.UserId <> p.OwnerUserId
  ),
  UserContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts AS p
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
    FROM RankedPostEdits AS rpe
    JOIN Users AS u
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
  CASE WHEN p.Tags IS NOT NULL THEN LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1 ELSE 0 END AS TagCount,
  COALESCE(led.LastEditorDisplayName, 'N/A') AS LastEditorDisplayName,
  COALESCE(led.LastEditDate, p.CreationDate) AS LastActivityDate,
  uc.TotalPostsOwned AS OwnerTotalPosts,
  uc.QuestionCount AS OwnerTotalQuestions,
  uc.AnswerCount AS OwnerTotalAnswers,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id AND c.UserId = p.OwnerUserId
  ) AS OwnerCommentCount,
  (
    SELECT
      MAX(CreationDate)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = p.Id AND ph.PostHistoryTypeId = 19 -- Question Protected
  ) AS LastProtectedDate,
  COALESCE(
    (
      SELECT
        STRING_AGG(lt.Name, ', ')
      FROM PostLinks AS pl
      JOIN LinkTypes AS lt
        ON pl.LinkTypeId = lt.Id
      WHERE
        pl.PostId = p.Id AND lt.Name = 'Duplicate'
    ),
    'None'
  ) AS DuplicateLinks
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u_owner
  ON p.OwnerUserId = u_owner.Id
LEFT JOIN LatestEditDetails AS led
  ON p.Id = led.PostId
LEFT JOIN UserContribution AS uc
  ON p.OwnerUserId = uc.OwnerUserId
WHERE
  p.PostTypeId IN (1, 2) -- Questions and Answers
  AND p.OwnerUserId IS NOT NULL
  AND p.ClosedDate IS NULL
  AND (
    p.Title LIKE '%SQL%' OR p.Body LIKE '%SQL%' OR p.Tags LIKE '%<sql>%'
  )
  AND EXISTS (
    SELECT
      1
    FROM Comments AS c
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
  uc.AnswerCount
HAVING
  COUNT(DISTINCT p.Id) > 1 -- Arbitrary condition to make the query more complex
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;
