-- {"query": "53053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 920} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT p.Id) AS TaggedPosts,
        SUM(p.Score) AS TotalTagScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName
),
UserTagContributions AS (
    SELECT 
        ua.UserId,
        tp.TagId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsInTag,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersInTag,
        SUM(p.Score) AS ScoreInTag
    FROM UserActivity ua
    JOIN Posts p ON ua.UserId = p.OwnerUserId
    JOIN TagPopularity tp ON p.Tags LIKE '%' || tp.TagName || '%'
    GROUP BY ua.UserId, tp.TagId
),
RankedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.TotalScore,
        ua.AvgViewCount,
        ua.Upvotes,
        ua.Downvotes,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        tp.TagName AS TopTag,
        utc.ScoreInTag AS TopTagScore,
        ROW_NUMBER() OVER (PARTITION BY tp.TagId ORDER BY utc.ScoreInTag DESC) AS RankInTag,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS OverallRank
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.UserId
    JOIN UserTagContributions utc ON u.Id = utc.UserId
    JOIN TagPopularity tp ON utc.TagId = tp.TagId
    WHERE tp.TagRank <= 10
    AND utc.ScoreInTag > 0
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    ru.QuestionsAsked,
    ru.AnswersGiven,
    ru.TotalScore,
    ru.AvgViewCount,
    ru.Upvotes - ru.Downvotes AS NetVotes,
    ru.GoldBadges + ru.SilverBadges + ru.BronzeBadges AS TotalBadges,
    ru.TopTag,
    ru.TopTagScore,
    ru.RankInTag,
    ru.OverallRank,
    (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.UserId = ru.Id) AS EditCount,
    (SELECT AVG(Score) FROM Comments c WHERE c.UserId = ru.Id) AS AvgCommentScore
FROM RankedUsers ru
WHERE ru.OverallRank <= 100
ORDER BY ru.OverallRank ASC, ru.RankInTag ASC;