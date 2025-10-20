-- {"query": "35075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 719} 
WITH TopActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    WHERE u.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
    ORDER BY TotalPosts + TotalComments + TotalVotes DESC
    LIMIT 100
),
UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.CommentCount) AS AvgCommentsPerPost
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '1 year'
    GROUP BY b.UserId
),
ActivePostLinks AS (
    SELECT
        pl.PostId,
        COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
        COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY pl.PostId
)
SELECT
    tau.UserId,
    tau.DisplayName,
    tau.TotalPosts,
    tau.TotalComments,
    tau.TotalVotes,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgScore,
    ups.TotalViews,
    ups.AvgCommentsPerPost,
    ubs.BadgeCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    COALESCE(apl.LinkedCount, 0) AS LinkedPostsLastYear,
    COALESCE(apl.DuplicateCount, 0) AS DuplicatePostsLastYear
FROM TopActiveUsers tau
LEFT JOIN UserPostStats ups ON ups.UserId = tau.UserId
LEFT JOIN UserBadgeStats ubs ON ubs.UserId = tau.UserId
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        SUM(apl.LinkedCount) AS LinkedCount,
        SUM(apl.DuplicateCount) AS DuplicateCount
    FROM ActivePostLinks apl
    JOIN Posts p ON p.Id = apl.PostId
    GROUP BY p.OwnerUserId
) apl ON apl.OwnerUserId = tau.UserId
ORDER BY tau.TotalPosts + tau.TotalComments + tau.TotalVotes DESC, ups.AvgScore DESC
LIMIT 50;