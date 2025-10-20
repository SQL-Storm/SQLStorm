-- {"query": "53015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 727} 

WITH TopTags AS (
    SELECT Id, TagName, Count
    FROM Tags
    ORDER BY Count DESC
    LIMIT 5
),
QuestionTags AS (
    SELECT p.Id AS QuestionId,
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= '2010-01-01'
    AND p.Score > 0
),
FilteredQuestions AS (
    SELECT qt.QuestionId,
           COUNT(DISTINCT tt.Id) AS TagMatchCount
    FROM QuestionTags qt
    JOIN TopTags tt ON qt.TagName = tt.TagName
    GROUP BY qt.QuestionId
    HAVING COUNT(DISTINCT tt.Id) >= 1
),
UserAnswers AS (
    SELECT a.OwnerUserId,
           SUM(a.Score) AS TotalAnswerScore,
           AVG(a.Score) AS AvgAnswerScore,
           COUNT(a.Id) AS AnswerCount,
           COUNT(DISTINCT a.ParentId) AS UniqueQuestionsAnswered,
           SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedCount
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    JOIN FilteredQuestions fq ON a.ParentId = fq.QuestionId
    WHERE a.PostTypeId = 2
    AND a.CreationDate >= '2010-01-01'
    AND a.Score > 0
    GROUP BY a.OwnerUserId
    HAVING COUNT(a.Id) >= 10
),
UserBadges AS (
    SELECT UserId,
           COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserVotes AS (
    SELECT v.UserId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM Votes v
    WHERE v.CreationDate >= '2010-01-01'
    GROUP BY v.UserId
)
SELECT ua.OwnerUserId,
       u.DisplayName,
       u.Reputation,
       ua.TotalAnswerScore,
       ua.AvgAnswerScore,
       ua.AnswerCount,
       ua.UniqueQuestionsAnswered,
       ua.AcceptedCount,
       COALESCE(ub.GoldBadges, 0) AS GoldBadges,
       COALESCE(ub.SilverBadges, 0) AS SilverBadges,
       COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(uv.UpVotesGiven, 0) AS UpVotesGiven,
       COALESCE(uv.DownVotesGiven, 0) AS DownVotesGiven,
       ROW_NUMBER() OVER (ORDER BY ua.TotalAnswerScore DESC) AS Rank
FROM UserAnswers ua
JOIN Users u ON ua.OwnerUserId = u.Id
LEFT JOIN UserBadges ub ON ua.OwnerUserId = ub.UserId
LEFT JOIN UserVotes uv ON ua.OwnerUserId = uv.UserId
WHERE u.Reputation > 1000
ORDER BY ua.TotalAnswerScore DESC
LIMIT 100;
