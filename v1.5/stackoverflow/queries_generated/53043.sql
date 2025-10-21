-- {"query": "53043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 923} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    GROUP BY v.PostId, p.OwnerUserId
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        COUNT(DISTINCT p.Id) AS TaggedPosts
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
    HAVING t.Count > 1000
),
TopUsers AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgPostScore,
        ua.TotalViews,
        ua.LastPostDate,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(cs.CommentCount, 0) AS CommentCount,
        COALESCE(cs.AvgCommentScore, 0) AS AvgCommentScore,
        SUM(va.Upvotes) AS TotalUpvotes,
        SUM(va.Downvotes) AS TotalDownvotes
    FROM UserActivity ua
    LEFT JOIN BadgeStats bs ON ua.UserId = bs.UserId
    LEFT JOIN CommentStats cs ON ua.UserId = cs.UserId
    LEFT JOIN VoteAnalysis va ON ua.UserId = va.UserId
    GROUP BY 
        ua.UserId, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.AvgPostScore, 
        ua.TotalViews, ua.LastPostDate, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, 
        cs.CommentCount, cs.AvgCommentScore
),
RankedUsers AS (
    SELECT 
        tu.*,
        ROW_NUMBER() OVER (ORDER BY tu.Reputation DESC, tu.GoldBadges DESC) AS Rank
    FROM TopUsers tu
    WHERE tu.QuestionCount > 10 AND tu.AnswerCount > 50
)
SELECT 
    ru.UserId,
    ru.Reputation,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AvgPostScore,
    ru.TotalViews,
    ru.LastPostDate,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.CommentCount,
    ru.AvgCommentScore,
    ru.TotalUpvotes,
    ru.TotalDownvotes,
    ru.Rank,
    (SELECT STRING_AGG(tp.TagName, ', ') 
     FROM TagPopularity tp 
     WHERE tp.TagCount > 5000) AS PopularTags
FROM RankedUsers ru
WHERE ru.Rank <= 100
ORDER BY ru.Rank;
