-- {"query": "53024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 805} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        SUM(v.BountyAmount) AS TotalBountiesEarned
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9)
    GROUP BY u.Id, u.Reputation
),
BadgeStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
EditActivity AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalEdits,
        COUNT(DISTINCT PostId) AS UniquePostsEdited
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY UserId
),
TagPopularity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        STRING_AGG(t.TagName, ', ') AS TopTags,
        SUM(p.Score) AS TotalTagScore
    FROM Posts p
    CROSS APPLY STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><') AS tag_split
    JOIN Tags t ON t.TagName = tag_split.value
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT t.TagName) > 5
),
RankedUsers AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.TotalQuestionViews,
        ua.AvgAnswerScore,
        ua.CommentsMade,
        ua.TotalBountiesEarned,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        ea.TotalEdits,
        ea.UniquePostsEdited,
        tp.TopTags,
        tp.TotalTagScore,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY ua.TotalQuestionViews DESC) AS ViewRank
    FROM UserActivity ua
    LEFT JOIN BadgeStats bs ON ua.UserId = bs.UserId
    LEFT JOIN EditActivity ea ON ua.UserId = ea.UserId
    LEFT JOIN TagPopularity tp ON ua.UserId = tp.UserId
    WHERE ua.Reputation > 10000
)
SELECT 
    ru.*,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ru.UserId) AND pl.LinkTypeId = 3) AS DuplicateLinks,
    (SELECT AVG(Score) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ru.UserId AND v.VoteTypeId = 2) AS AvgUpvoteScore
FROM RankedUsers ru
WHERE ru.ReputationRank <= 100
ORDER BY ru.Reputation DESC, ru.TotalQuestionViews DESC;
