-- {"query": "13021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 750} 
WITH UserActivity AS (
  SELECT 
    U.Id AS UserId,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersProvided,
    SUM(CASE WHEN P.Score > 10 THEN 1 ELSE 0 END) AS HighScoringPosts,
    MAX(P.CreationDate) AS LastPostDate,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) DESC) AS QuestionRank
  FROM Users U
  LEFT JOIN Posts P ON U.Id = P.OwnerUserId
  WHERE P.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '6 months'
    AND (P.PostTypeId = 1 OR P.PostTypeId = 2)
  GROUP BY U.Id
),
TopEditors AS (
  SELECT 
    UserId,
    COUNT(*) AS TotalEdits,
    COUNT(*) FILTER (WHERE PostHistoryTypeId IN (4, 5, 6)) AS TitleBodyTagEdits
  FROM PostHistory
  WHERE PostHistoryTypeId BETWEEN 4 AND 6
    AND CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '6 months'
  GROUP BY UserId
),
UserBadges AS (
  SELECT 
    UserId,
    COUNT(DISTINCT CASE WHEN Class = 1 THEN Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN Class = 2 THEN Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN Class = 3 THEN Id END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
)
SELECT 
  U.DisplayName,
  COALESCE(UA.QuestionsAsked, 0) AS QuestionsAsked,
  COALESCE(UA.AnswersProvided, 0) AS AnswersProvided,
  COALESCE(UA.HighScoringPosts, 0) AS HighScoringPosts,
  COALESCE(TE.TotalEdits, 0) AS TotalEdits,
  COALESCE(TE.TitleBodyTagEdits, 0) AS TitleBodyTagEdits,
  COALESCE(UB.GoldBadges, 0) AS GoldBadges,
  COALESCE(UB.SilverBadges, 0) AS SilverBadges,
  COALESCE(UB.BronzeBadges, 0) AS BronzeBadges,
  CASE
    WHEN COALESCE(UA.QuestionRank, 0) <= 10 THEN 'Top 10 Question Askers'
    ELSE 'Regular Contributor'
  END AS ContributorStatus
FROM Users U
LEFT JOIN UserActivity UA ON U.Id = UA.UserId
LEFT JOIN TopEditors TE ON U.Id = TE.UserId
LEFT JOIN UserBadges UB ON U.Id = UB.UserId
WHERE U.Reputation > 1000
  AND (U.Location IS NOT NULL OR U.AboutMe IS NOT NULL)
ORDER BY UA.QuestionsAsked DESC NULLS LAST, TE.TotalEdits DESC NULLS LAST
LIMIT 50;