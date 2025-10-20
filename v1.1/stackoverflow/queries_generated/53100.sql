-- {"query": "53100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 855} 

WITH TagExplode AS (
    SELECT 
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TopTags AS (
    SELECT 
        TagName,
        COUNT(DISTINCT PostId) AS QuestionCount
    FROM TagExplode
    GROUP BY TagName
    ORDER BY QuestionCount DESC
    LIMIT 10
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges
    GROUP BY UserId
),
UserVotes AS (
    SELECT 
        UserId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY UserId
),
UserTagSpecialization AS (
    SELECT 
        p.OwnerUserId AS UserId,
        te.TagName,
        COUNT(DISTINCT p.Id) AS AnswersInTag,
        SUM(p.Score) AS ScoreInTag,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC) AS TagRank
    FROM Posts p
    JOIN TagExplode te ON te.PostId = p.ParentId
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId, te.TagName
    HAVING COUNT(DISTINCT p.Id) > 10
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.QuestionScore,
    ua.AnswerScore,
    ua.AvgAnswerScore,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    uv.UpvotesGiven,
    uv.DownvotesGiven,
    uts.TagName AS TopTag,
    uts.AnswersInTag AS TopTagAnswers,
    uts.ScoreInTag AS TopTagScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.UserId) AS CommentsMade,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = ua.UserId AND ph.PostHistoryTypeId IN (4,5,6)) AS EditsMade,
    RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank
FROM UserActivity ua
JOIN UserBadges ub ON ub.UserId = ua.UserId
JOIN UserVotes uv ON uv.UserId = ua.UserId
JOIN UserTagSpecialization uts ON uts.UserId = ua.UserId AND uts.TagRank = 1
JOIN TopTags tt ON tt.TagName = uts.TagName
WHERE ua.AnswersGiven > 50 AND ub.GoldBadges >= 1
ORDER BY ua.Reputation DESC
LIMIT 500;
