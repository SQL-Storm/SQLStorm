-- {"query": "43091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 652} 
WITH UserActivity AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
           SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts,
           MAX(p.Score) AS HighestScore,
           COUNT(DISTINCT b.Id) AS TotalBadges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) DESC) AS QuestionRank,
           RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) DESC) AS AnswerRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > cast('2024-10-01' as date) - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName
),
TopContributors AS (
    SELECT UserId,
           DisplayName,
           QuestionsAsked,
           AnswersGiven,
           (QuestionsAsked + AnswersGiven) AS TotalContributions,
           PositiveScorePosts,
           HighestScore,
           TotalBadges,
           GoldBadges,
           SilverBadges,
           BronzeBadges
    FROM UserActivity
    WHERE QuestionRank <= 10 OR AnswerRank <= 10
)
SELECT tc.DisplayName,
       tc.QuestionsAsked,
       tc.AnswersGiven,
       tc.TotalContributions,
       tc.PositiveScorePosts,
       tc.HighestScore,
       tc.TotalBadges,
       tc.GoldBadges,
       tc.SilverBadges,
       tc.BronzeBadges,
       ph.RevisionGUID,
       ph.CreationDate AS LastEditDate,
       pt.Name AS PostTypeName
FROM TopContributors tc
JOIN Posts p ON tc.UserId = p.OwnerUserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8)
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE p.LastEditDate > cast('2024-10-01' as date) - INTERVAL '3 months'
ORDER BY tc.TotalContributions DESC, ph.CreationDate DESC
LIMIT 100;