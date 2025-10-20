-- {"query": "53002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 981} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN v.BountyAmount ELSE 0 END) AS TotalBounty
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= '2020-01-01'
    GROUP BY v.PostId, p.OwnerUserId
),
AggregatedVotes AS (
    SELECT 
        UserId,
        SUM(Upvotes) AS TotalUpvotes,
        SUM(Downvotes) AS TotalDownvotes,
        SUM(TotalBounty) AS TotalBountyEarned
    FROM VoteAnalysis
    GROUP BY UserId
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagUsage,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName, t.Count
    HAVING SUM(p.ViewCount) > 100000
),
UserTagAffinity AS (
    SELECT 
        u.Id AS UserId,
        t.TagId,
        COUNT(DISTINCT p.Id) AS PostsInTag,
        SUM(p.Score) AS ScoreInTag
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    INNER JOIN TagPopularity t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.CreationDate >= '2020-01-01'
    GROUP BY u.Id, t.TagId
    HAVING COUNT(DISTINCT p.Id) > 10
),
TopUsersPerTag AS (
    SELECT 
        TagId,
        UserId,
        ScoreInTag,
        ROW_NUMBER() OVER (PARTITION BY TagId ORDER BY ScoreInTag DESC) AS Rank
    FROM UserTagAffinity
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.AvgViewCount,
    ua.LastPostDate,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AnswerScore,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.LatestBadgeDate,
    av.TotalUpvotes,
    av.TotalDownvotes,
    av.TotalBountyEarned,
    tp.TagName,
    tut.ScoreInTag,
    tut.Rank AS TagRank
FROM UserActivity ua
LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN AggregatedVotes av ON ua.UserId = av.UserId
INNER JOIN TopUsersPerTag tut ON ua.UserId = tut.UserId AND tut.Rank <= 5
INNER JOIN TagPopularity tp ON tut.TagId = tp.TagId
WHERE ua.Reputation > 5000
ORDER BY ua.Reputation DESC, tp.TagUsage DESC
LIMIT 1000;
