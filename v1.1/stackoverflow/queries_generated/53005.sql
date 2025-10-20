-- {"query": "53005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 745} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
TopTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId, p.OwnerUserId
),
CommentStats AS (
    SELECT 
        PostId,
        COUNT(Id) AS CommentCount,
        AVG(Score) AS AvgCommentScore
    FROM Comments
    GROUP BY PostId
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastPostDate,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tt.Tag AS TopTag,
    tt.TagCount,
    SUM(va.Upvotes) AS TotalUpvotes,
    SUM(va.Downvotes) AS TotalDownvotes,
    AVG(cs.CommentCount) AS AvgCommentsPerPost,
    AVG(cs.AvgCommentScore) AS OverallAvgCommentScore
FROM UserActivity ua
LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN TopTags tt ON ua.UserId = tt.UserId AND tt.TagRank = 1
LEFT JOIN VoteAnalysis va ON ua.UserId = va.UserId
LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
LEFT JOIN CommentStats cs ON p.Id = cs.PostId
WHERE ua.Reputation > 1000
GROUP BY 
    ua.UserId, ua.Reputation, ua.PostCount, ua.TotalScore, ua.AvgScore, ua.LastPostDate,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, tt.Tag, tt.TagCount
ORDER BY ua.TotalScore DESC
LIMIT 100;