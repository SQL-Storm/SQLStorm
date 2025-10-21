-- {"query": "53046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 810} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation
),
TopTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
VoteAnalysis AS (
    SELECT 
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8,9) AND v.BountyAmount IS NOT NULL) AS AvgBounty
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
PostHistoryStats AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditedPosts,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditsMade
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
)
SELECT 
    us.UserId,
    us.Reputation,
    us.QuestionsAsked,
    us.AnswersGiven,
    us.AvgAnswerScore,
    us.TotalBadges,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    tt.Tag AS TopTag,
    tt.TagCount AS TopTagCount,
    va.UpvotesReceived,
    va.DownvotesReceived,
    va.AvgBounty,
    cs.TotalComments,
    cs.AvgCommentScore,
    phs.EditedPosts,
    phs.EditsMade,
    RANK() OVER (ORDER BY us.GoldBadges DESC, us.Reputation DESC) AS OverallRank
FROM UserStats us
LEFT JOIN TopTags tt ON us.UserId = tt.UserId AND tt.rn = 1
LEFT JOIN VoteAnalysis va ON us.UserId = va.UserId
LEFT JOIN CommentStats cs ON us.UserId = cs.UserId
LEFT JOIN PostHistoryStats phs ON us.UserId = phs.UserId
WHERE us.GoldBadges > 0
ORDER BY OverallRank
LIMIT 100;
