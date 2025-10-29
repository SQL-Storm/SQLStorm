-- {"query": "4131.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1627}
WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS PostCount,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  UserVoteStats AS (
    SELECT
      UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS Favorites,
      SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Votes v
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  PostRevisionDetails AS (
    SELECT
      ph.PostId,
      COUNT(ph.Id) AS RevisionCount,
      MAX(ph.CreationDate) AS LastRevisionDate,
      ph.UserId AS LastEditorUserId,
      ph.UserDisplayName AS LastEditorDisplayName,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      ph.PostId,
      ph.UserId,
      ph.UserDisplayName
  ),
  UserScoreDistribution AS (
    SELECT
      OwnerUserId,
      PostTypeId,
      SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCount,
      SUM(CASE WHEN Score < 0 THEN 1 ELSE 0 END) AS NegativeScoreCount,
      AVG(Score) AS AverageScore
    FROM Posts
    WHERE
      OwnerUserId IS NOT NULL AND Score IS NOT NULL
    GROUP BY
      OwnerUserId,
      PostTypeId
  ),
  latest_history AS (
    SELECT
      p.OwnerUserId,
      ph.PostId,
      MAX(ph.Id) AS LastHistoryId
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    GROUP BY
      p.OwnerUserId,
      ph.PostId
  ),
  -- For each user pick the latest history id among their posts
  user_latest_history AS (
    SELECT
      OwnerUserId AS UserId,
      MAX(LastHistoryId) AS LastHistoryId
    FROM latest_history
    GROUP BY OwnerUserId
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(upc.PostCount, 0) AS TotalPosts,
  COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
  COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
  COALESCE(uvs.UpVotes, 0) AS TotalUpVotes,
  COALESCE(uvs.DownVotes, 0) AS TotalDownVotes,
  COALESCE(uvs.Favorites, 0) AS TotalFavorites,
  COALESCE(uvs.AcceptedAnswers, 0) AS AcceptedAnswers,
  COALESCE(prd.RevisionCount, 0) AS TotalRevisions,
  prd.LastRevisionDate,
  prd.LastEditorDisplayName AS LastEditorName,
  COALESCE(prd.BodyEdits, 0) AS BodyRevisionCount,
  COALESCE(prd.TitleEdits, 0) AS TitleRevisionCount,
  COALESCE(prd.TagEdits, 0) AS TagRevisionCount,
  CASE
    WHEN u.Reputation > 100000 THEN 'Legendary'
    WHEN u.Reputation > 50000 THEN 'Expert'
    WHEN u.Reputation > 10000 THEN 'Advanced'
    WHEN u.Reputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS ReputationLevel,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 1
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 2
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Class = 3
  ) AS BronzeBadges,
  COALESCE(usd_q.PositiveScoreCount, 0) AS QuestionPositiveScores,
  COALESCE(usd_q.NegativeScoreCount, 0) AS QuestionNegativeScores,
  usd_q.AverageScore AS AverageQuestionScore,
  COALESCE(usd_a.PositiveScoreCount, 0) AS AnswerPositiveScores,
  COALESCE(usd_a.NegativeScoreCount, 0) AS AnswerNegativeScores,
  usd_a.AverageScore AS AverageAnswerScore,
  pht.Name AS LastPostHistoryAction,
  ph_last.CreationDate AS LastPostHistoryDate,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Site'
    ELSE 'External Website'
  END AS WebsiteCategory,
  CASE
    WHEN u.AboutMe IS NULL OR u.AboutMe = '' THEN 'No Bio'
    WHEN LENGTH(u.AboutMe) > 500 THEN 'Extensive Bio'
    ELSE 'Standard Bio'
  END AS BioLengthCategory,
  CASE
    WHEN u.DownVotes > u.UpVotes * 5 THEN 'High Ratio'
    ELSE 'Normal Ratio'
  END AS VoteRatioCategory,
  CASE
    WHEN u.CreationDate < CAST('2024-10-01' AS date) - INTERVAL '5' YEAR THEN 'Established'
    WHEN u.CreationDate < CAST('2024-10-01' AS date) - INTERVAL '1' YEAR THEN 'Active'
    ELSE 'New'
  END AS AccountAgeCategory
FROM Users u
LEFT JOIN UserPostCounts upc
  ON u.Id = upc.OwnerUserId
LEFT JOIN UserVoteStats uvs
  ON u.Id = uvs.UserId
LEFT JOIN PostRevisionDetails prd
  ON u.Id = prd.LastEditorUserId
LEFT JOIN UserScoreDistribution usd_q
  ON u.Id = usd_q.OwnerUserId AND usd_q.PostTypeId = 1
LEFT JOIN UserScoreDistribution usd_a
  ON u.Id = usd_a.OwnerUserId AND usd_a.PostTypeId = 2
LEFT JOIN user_latest_history ulh
  ON u.Id = ulh.UserId
LEFT JOIN PostHistory ph_last
  ON ulh.LastHistoryId = ph_last.Id
LEFT JOIN PostHistoryTypes pht
  ON ph_last.PostHistoryTypeId = pht.Id
GROUP BY
  u.Id,
  u.DisplayName,
  upc.PostCount,
  upc.QuestionCount,
  upc.AnswerCount,
  uvs.UpVotes,
  uvs.DownVotes,
  uvs.Favorites,
  uvs.AcceptedAnswers,
  prd.RevisionCount,
  prd.LastRevisionDate,
  prd.LastEditorDisplayName,
  prd.BodyEdits,
  prd.TitleEdits,
  prd.TagEdits,
  u.Reputation,
  usd_q.PositiveScoreCount,
  usd_q.NegativeScoreCount,
  usd_q.AverageScore,
  usd_a.PositiveScoreCount,
  usd_a.NegativeScoreCount,
  usd_a.AverageScore,
  pht.Name,
  ph_last.CreationDate,
  u.WebsiteUrl,
  u.AboutMe,
  u.DownVotes,
  u.UpVotes,
  u.CreationDate,
  ulh.LastHistoryId
ORDER BY
  u.Reputation DESC,
  TotalQuestions DESC
LIMIT 1000;