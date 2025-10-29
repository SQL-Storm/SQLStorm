-- {"query": "4242.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1267} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate AS EditDate,
      ph.UserId AS EditorUserId,
      ph.Comment AS EditComment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  LatestPostEdits AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      EditDate,
      EditorUserId,
      EditComment
    FROM RankedPostEdits
    WHERE
      rn = 1
  ),
  PostEditSummary AS (
    SELECT
      PostId,
      MAX(CASE WHEN PostHistoryTypeId = 4 THEN EditDate ELSE NULL END) AS LastTitleEditDate,
      MAX(CASE WHEN PostHistoryTypeId = 5 THEN EditDate ELSE NULL END) AS LastBodyEditDate,
      MAX(CASE WHEN PostHistoryTypeId = 6 THEN EditDate ELSE NULL END) AS LastTagsEditDate,
      COUNT(CASE WHEN PostHistoryTypeId = 4 THEN 1 ELSE NULL END) AS TitleEditCount,
      COUNT(CASE WHEN PostHistoryTypeId = 5 THEN 1 ELSE NULL END) AS BodyEditCount,
      COUNT(CASE WHEN PostHistoryTypeId = 6 THEN 1 ELSE NULL END) AS TagsEditCount,
      COUNT(DISTINCT EditorUserId) AS DistinctEditors
    FROM LatestPostEdits
    GROUP BY
      PostId
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS QuestionCount,
      SUM(p.AnswerCount) AS TotalAnswerCount,
      SUM(p.FavoriteCount) AS TotalFavoriteCount,
      AVG(CAST(p.Score AS REAL)) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostCreationDate
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 -- Questions
    GROUP BY
      p.OwnerUserId
  )
SELECT
  COALESCE(u.DisplayName, 'Unknown User') AS UserName,
  COALESCE(up.QuestionCount, 0) AS NumberOfQuestions,
  COALESCE(up.TotalAnswerCount, 0) AS TotalAnswersToHisQuestions,
  COALESCE(up.TotalFavoriteCount, 0) AS TotalFavoritesOnHisQuestions,
  COALESCE(up.AvgPostScore, 0.0) AS AverageQuestionScore,
  COALESCE(pess.TitleEditCount, 0) AS NumberOfTitleEdits,
  COALESCE(pess.BodyEditCount, 0) AS NumberOfBodyEdits,
  COALESCE(pess.TagsEditCount, 0) AS NumberOfTagEdits,
  CASE
    WHEN pess.LastTitleEditDate > pess.LastBodyEditDate
    AND pess.LastTitleEditDate > pess.LastTagsEditDate THEN 'Title'
    WHEN pess.LastBodyEditDate > pess.LastTitleEditDate
    AND pess.LastBodyEditDate > pess.LastTagsEditDate THEN 'Body'
    WHEN pess.LastTagsEditDate > pess.LastTitleEditDate
    AND pess.LastTagsEditDate > pess.LastBodyEditDate THEN 'Tags'
    ELSE 'Mixed/None'
  END AS MostRecentlyEditedField,
  CASE
    WHEN u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' AND u.Reputation > 10000 THEN 'Experienced Contributor'
    WHEN u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' AND u.Reputation > 1000 THEN 'Intermediate Contributor'
    ELSE 'New Contributor'
  END AS ContributorTier,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Name = 'Famous Question'
    ) THEN 'Has Famous Question Badge'
    ELSE 'No Famous Question Badge'
  END AS FamousQuestionBadgeStatus,
  LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PreviousReputation,
  (
    SELECT
      COUNT(*)
    FROM Posts AS p_inner
    WHERE
      p_inner.OwnerUserId = u.Id AND p_inner.ClosedDate IS NOT NULL
  ) AS ClosedQuestionCount,
  UPPER(SUBSTR(COALESCE(u.Location, 'N/A'), 1, 3)) AS LocationAbbreviation,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteType,
  CASE
    WHEN u.AccountId IS NULL THEN 'No Account Link'
    ELSE 'Account Linked'
  END AS AccountLinkingStatus
FROM Users AS u
LEFT OUTER JOIN UserPostActivity AS up
  ON u.Id = up.OwnerUserId
LEFT OUTER JOIN PostEditSummary AS pess
  ON u.Id = pess.PostId
WHERE
  u.Id > 0
  AND u.Reputation BETWEEN 100 AND 100000
ORDER BY
  u.Reputation DESC,
  up.QuestionCount DESC,
  pess.BodyEditCount DESC
LIMIT 100;