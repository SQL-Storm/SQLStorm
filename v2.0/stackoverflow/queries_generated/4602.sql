-- {"query": "4602.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1444} 

WITH
  RankedPosts AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS ViewRank,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.FavoriteCount DESC) AS FavRank
    FROM
      Posts AS p
    WHERE
      p.CreationDate >= DATE('now', '-365 day')
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
      AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
      SUM(p.ViewCount) AS TotalViews,
      SUM(p.FavoriteCount) AS TotalFavorites
    FROM
      Users AS u
    LEFT OUTER JOIN
      Posts AS p
      ON u.Id = p.OwnerUserId
    WHERE
      u.Reputation > 1000
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  RecentActivity AS (
    SELECT
      ph.PostId,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 END) AS BodyEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotes,
      MAX(ph.CreationDate) AS LastHistoryDate
    FROM
      PostHistory AS ph
    WHERE
      ph.CreationDate >= DATE('now', '-180 day')
    GROUP BY
      ph.PostId
  )
SELECT
  COALESCE(ups.DisplayName, 'Community') AS UserName,
  COALESCE(ups.QuestionCount, 0) AS NumQuestions,
  COALESCE(ups.AnswerCount, 0) AS NumAnswers,
  COALESCE(ups.AvgQuestionScore, 0.0) AS AvgQScore,
  COALESCE(ups.AvgAnswerScore, 0.0) AS AvgAScore,
  COALESCE(ups.TotalViews, 0) AS UserTotalViews,
  COALESCE(ups.TotalFavorites, 0) AS UserTotalFavorites,
  rp_q.Score AS TopQuestionScore,
  rp_a.Score AS TopAnswerScore,
  rp_q.ViewCount AS TopQuestionViews,
  rp_a.ViewCount AS TopAnswerViews,
  COALESCE(ra.BodyEdits, 0) AS RecentBodyEdits,
  COALESCE(ra.CloseVotes, 0) AS RecentCloseVotes,
  CASE
    WHEN ups.UserId IS NULL THEN 'Anonymous/Deleted'
    WHEN ups.DisplayName IS NULL THEN 'Unnamed User'
    WHEN ups.DisplayName LIKE '%[^a-zA-Z0-9 ]%' THEN 'Special Chars User'
    ELSE 'Standard User'
  END AS UserType,
  CASE
    WHEN ups.TotalFavorites > 1000 THEN 'Power User'
    WHEN ups.TotalFavorites > 100 THEN 'Active User'
    ELSE 'Regular User'
  END AS UserActivityLevel,
  UPPER(SUBSTR(COALESCE(ups.DisplayName, 'N/A'), 1, 3)) AS UserInitialPrefix
FROM
  UserPostStats AS ups
LEFT OUTER JOIN
  RankedPosts AS rp_q
  ON ups.UserId = rp_q.OwnerUserId AND rp_q.PostTypeId = 1 AND rp_q.ScoreRank = 1
LEFT OUTER JOIN
  RankedPosts AS rp_a
  ON ups.UserId = rp_a.OwnerUserId AND rp_a.PostTypeId = 2 AND rp_a.ScoreRank = 1
LEFT OUTER JOIN
  RecentActivity AS ra
  ON ups.UserId = ra.PostId -- This is a conceptual join, assuming PostId in RecentActivity can map to OwnerUserId in UserPostStats for demonstration
WHERE
  ups.QuestionCount > 0 OR ups.AnswerCount > 0
UNION
SELECT
  'Community User' AS UserName,
  COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS NumQuestions,
  COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS NumAnswers,
  AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
  AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
  SUM(p.ViewCount) AS TotalViews,
  SUM(p.FavoriteCount) AS TotalFavorites,
  MAX(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS TopQuestionScore,
  MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS TopAnswerScore,
  MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS TopQuestionViews,
  MAX(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE NULL END) AS TopAnswerViews,
  COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 END) AS RecentBodyEdits,
  COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS RecentCloseVotes,
  'System Account' AS UserType,
  'System Level' AS UserActivityLevel,
  'SYS' AS UserInitialPrefix
FROM
  Posts AS p
LEFT OUTER JOIN
  PostHistory AS ph
  ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 16 -- Community Owned
WHERE
  p.OwnerUserId = -1 AND p.CommunityOwnedDate IS NOT NULL
GROUP BY
  UserName;
