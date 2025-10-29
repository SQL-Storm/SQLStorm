-- {"query": "4874.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1362}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    GROUP BY
      p.OwnerUserId
  ),
  UserEditSummary AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS EditedPostCount,
      MIN(rpe.EditDate) AS FirstEditDate,
      MAX(rpe.EditDate) AS LastEditDate
    FROM RankedPostEdits rpe
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
  ),
  UserVoteSummary AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesGiven,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesGiven,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS FavoritesGiven,
      SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Votes v
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  )
SELECT
  u.DisplayName,
  u.Reputation,
  upa.PostCount,
  upa.QuestionCount,
  upa.AnswerCount,
  upa.AvgScore,
  COALESCE(ues.EditedPostCount, 0) AS TotalEditsMade,
  COALESCE(uvs.UpVotesGiven, 0) AS TotalUpvotesGiven,
  COALESCE(uvs.DownVotesGiven, 0) AS TotalDownvotesGiven,
  COALESCE(uvs.FavoritesGiven, 0) AS TotalFavoritesGiven,
  COALESCE(uvs.AcceptedAnswers, 0) AS TotalAcceptedAnswers,
  CASE
    WHEN u.Views > 1000000 THEN 'Highly Viewed'
    WHEN u.Views > 100000 THEN 'Moderately Viewed'
    ELSE 'Standard View'
  END AS ViewCategory,
  CASE
    WHEN CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate < INTERVAL '30 days' THEN 'New User'
    WHEN u.LastAccessDate IS NOT NULL AND CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate > INTERVAL '365 days' THEN 'Inactive User'
    ELSE 'Active User'
  END AS UserStatus,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
    ELSE 'No Website'
  END AS WebsiteStatus,
  LOWER(SUBSTRING(u.AboutMe FROM 1 FOR 50)) AS AboutMeSnippet,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = u.Id AND b.Name ILIKE '%gold%' AND b.Class = 1
    ) THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS GoldBadgeStatus,
  CAST('2024-10-01 12:34:56' AS timestamp) AS QueryExecutionTime
FROM Users u
LEFT JOIN UserPostActivity upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN UserEditSummary ues
  ON u.Id = ues.UserId
LEFT JOIN UserVoteSummary uvs
  ON u.Id = uvs.UserId
WHERE
  u.Reputation > 1000
  AND u.DisplayName IS NOT NULL
  AND (COALESCE(upa.AnswerCount, 0) > 5 OR COALESCE(upa.QuestionCount, 0) > 5)
  AND u.Id NOT IN (
    SELECT UserId FROM Votes WHERE VoteTypeId = 10
  )

UNION

SELECT
  'Community User' AS DisplayName,
  0 AS Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) AS AvgScore,
  COUNT(DISTINCT ph.PostId) AS TotalEditsMade,
  0 AS TotalUpvotesGiven,
  0 AS TotalDownvotesGiven,
  0 AS TotalFavoritesGiven,
  0 AS TotalAcceptedAnswers,
  'Standard View' AS ViewCategory,
  'Active User' AS UserStatus,
  'No Website' AS WebsiteStatus,
  NULL AS AboutMeSnippet,
  'No Gold Badge' AS GoldBadgeStatus,
  CAST('2024-10-01 12:34:56' AS timestamp) AS QueryExecutionTime
FROM Posts p
LEFT JOIN PostHistory ph
  ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
WHERE
  p.OwnerUserId = -1
GROUP BY
  p.OwnerUserId;