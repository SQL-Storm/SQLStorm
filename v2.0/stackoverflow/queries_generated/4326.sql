-- {"query": "4326.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1221} 

WITH
  RankedUserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS PostsCount,
      COUNT(DISTINCT c.Id) AS CommentsCount,
      ROW_NUMBER() OVER (
        ORDER BY
          u.Reputation DESC,
          u.Id
      ) AS ReputationRank,
      AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
      MAX(p.CreationDate) OVER (PARTITION BY u.Id) AS LastPostDate
    FROM
      Users AS u
      LEFT JOIN Posts AS p
        ON u.Id = p.OwnerUserId
      LEFT JOIN Comments AS c
        ON u.Id = c.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      SUM(p.AnswerCount) AS TotalAnswersForTag,
      COUNT(DISTINCT p.Id) AS PostsWithTag,
      AVG(CAST(p.FavoriteCount AS DECIMAL(10, 2))) AS AvgFavoritesPerPost,
      STRING_AGG(DISTINCT pu.DisplayName, ', ') WITHIN GROUP (
        ORDER BY
          pu.DisplayName
      ) AS PopularUsersForTag
    FROM
      Tags AS t
      JOIN Posts AS p
        ON ',' || REPLACE(p.Tags, '><', ',') || ',' LIKE '%,' || t.TagName || ',%'
      LEFT JOIN Users AS pu
        ON p.OwnerUserId = pu.Id
    WHERE
      t.TagName NOT IN ('sql', 'database')
      AND p.PostTypeId = 1
    GROUP BY
      t.TagName
    HAVING
      COUNT(DISTINCT p.Id) > 50
  ),
  HighReputationQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      u.DisplayName AS OwnerDisplayName,
      CAST(
        p.CreationDate AS DATE
      ) AS QuestionDate,
      CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted' ELSE 'Not Accepted' END AS AcceptanceStatus,
      RANK() OVER (
        ORDER BY
          p.Score DESC,
          p.AnswerCount DESC
      ) AS QuestionRank
    FROM
      Posts AS p
      JOIN Users AS u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.Score > 100
      AND p.CreationDate >= DATE('now', '-365 day')
  )
SELECT
  COALESCE(rua.DisplayName, 'Unknown User') AS UserName,
  rua.Reputation,
  rua.ReputationRank,
  rua.AvgPostScore,
  COALESCE(tp.TagName, 'General') AS TopTag,
  COALESCE(tp.TotalAnswersForTag, 0) AS TagAnswers,
  COALESCE(tp.AvgFavoritesPerPost, 0) AS TagAvgFavorites,
  hrq.Title AS HighRankedQuestionTitle,
  hrq.Score AS HighRankedQuestionScore,
  CASE
    WHEN LENGTH(COALESCE(u.AboutMe, '')) > 200
    THEN SUBSTRING(u.AboutMe, 1, 200) || '...'
    ELSE u.AboutMe
  END AS TruncatedAboutMe,
  CASE
    WHEN rua.LastPostDate BETWEEN DATE('now', '-7 day') AND DATE('now') THEN 'Active in Last Week'
    WHEN rua.LastPostDate BETWEEN DATE('now', '-30 day') AND DATE('now') THEN 'Active in Last Month'
    ELSE 'Less Active'
  END AS ActivityLevel,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        Badges AS b
      WHERE
        b.UserId = u.Id AND b.Name LIKE '%Expert%' AND b.Class = 1
    ) THEN 'Gold Expert Badge Holder'
    ELSE 'No Gold Expert Badge'
  END AS ExpertBadgeStatus
FROM
  RankedUserActivity AS rua
  LEFT JOIN Users AS u
    ON rua.UserId = u.Id
  LEFT JOIN (
    SELECT
      TagName,
      TotalAnswersForTag,
      AvgFavoritesPerPost,
      ROW_NUMBER() OVER (ORDER BY TotalAnswersForTag DESC) AS rn
    FROM
      TagPopularity
  ) AS tp
    ON tp.rn = 1
  LEFT JOIN HighReputationQuestions AS hrq
    ON hrq.QuestionRank = 1
WHERE
  rua.Reputation > 5000
  AND COALESCE(u.Location, '') <> ''
  AND (
    rua.QuestionsAsked + rua.AnswersGiven
  ) > 10
ORDER BY
  rua.Reputation DESC,
  tp.TotalAnswersForTag DESC
LIMIT 100;
