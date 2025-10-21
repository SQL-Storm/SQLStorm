-- {"query": "53085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 887} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteAnalytics AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes v
    WHERE v.CreationDate >= '2020-01-01'
    GROUP BY v.PostId
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TagUsage,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 1000
),
ComplexJoin AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.PostCount,
        ua.TotalScore,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.LastPostDate,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        AVG(va.Upvotes) AS AvgUpvotesPerPost,
        SUM(va.Downvotes) AS TotalDownvotes,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts,
        STRING_AGG(tt.TagName, ', ') AS TopTagsUsed
    FROM UserActivity ua
    INNER JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
    LEFT JOIN VoteAnalytics va ON p.Id = va.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    LEFT JOIN TopTags tt ON p.Tags LIKE '%' || tt.TagName || '%' AND tt.TagRank <= 10
    WHERE ua.Reputation > 10000
    AND ua.LastPostDate >= '2022-01-01'
    GROUP BY 
        ua.UserId, ua.Reputation, ua.PostCount, ua.TotalScore, 
        ua.QuestionCount, ua.AnswerCount, ua.LastPostDate,
        bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
)
SELECT 
    cj.*,
    RANK() OVER (PARTITION BY cj.GoldBadges ORDER BY cj.TotalScore DESC) AS ScoreRank,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cj.AvgUpvotesPerPost) OVER (PARTITION BY cj.GoldBadges) AS MedianUpvotes
FROM ComplexJoin cj
WHERE cj.PostCount > 50
ORDER BY cj.Reputation DESC, cj.GoldBadges DESC
LIMIT 1000;
