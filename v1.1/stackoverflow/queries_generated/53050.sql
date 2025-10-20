-- {"query": "53050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 931} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT v.Id) AS TotalVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate >= '2010-01-01' AND p.CreationDate < '2023-01-01'
    GROUP BY u.Id
),
UserBadges AS (
    SELECT 
        UserId,
        COUNT(Id) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges
    GROUP BY UserId
),
PostHistoryStats AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    GROUP BY t.Id, t.TagName, t.Count
),
TopUsersPerTag AS (
    SELECT 
        tp.TagId,
        ua.UserId,
        ua.TotalPosts,
        ROW_NUMBER() OVER (PARTITION BY tp.TagId ORDER BY ua.TotalPosts DESC) AS Rank
    FROM TagPopularity tp
    JOIN Posts p ON p.Tags LIKE '%' || (SELECT TagName FROM Tags WHERE Id = tp.TagId) || '%'
    JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
)
SELECT 
    u.DisplayName,
    u.Reputation,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgPostScore,
    ua.TotalViews,
    ua.Upvotes,
    ua.Downvotes,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    AVG(phs.EditCount) AS AvgEditsPerPost,
    tp.TagName,
    tupt.Rank AS TagRank
FROM Users u
JOIN UserActivity ua ON u.Id = ua.UserId
JOIN UserBadges ub ON u.Id = ub.UserId
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostHistoryStats phs ON p.Id = phs.PostId
JOIN TagPopularity tp ON p.Tags LIKE '%' || tp.TagName || '%'
JOIN TopUsersPerTag tupt ON ua.UserId = tupt.UserId AND tp.TagId = tupt.TagId
WHERE u.Reputation > 10000 AND tupt.Rank <= 10
GROUP BY u.DisplayName, u.Reputation, ua.TotalPosts, ua.QuestionCount, ua.AnswerCount, ua.AvgPostScore, ua.TotalViews, ua.Upvotes, ua.Downvotes, ub.BadgeCount, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, tp.TagName, tupt.Rank
ORDER BY u.Reputation DESC, tp.TagUsageCount DESC
LIMIT 100;
