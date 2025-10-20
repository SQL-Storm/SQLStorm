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
    WHERE u.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
    ORDER BY COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) + COUNT(DISTINCT v.Id) DESC
    LIMIT 100
),
UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.CommentCount) AS AvgCommentsPerPost
    FROM Posts p
    WHERE p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY b.UserId
),
ActivePostLinks AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
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
        p.OwnerUserId AS OwnerUserId,
        SUM(apl.LinkedCount) AS LinkedCount,
        SUM(apl.DuplicateCount) AS DuplicateCount
    FROM ActivePostLinks apl
    JOIN Posts p ON p.Id = apl.PostId
    GROUP BY p.OwnerUserId
) apl ON apl.OwnerUserId = tau.UserId
ORDER BY (tau.TotalPosts + tau.TotalComments + tau.TotalVotes) DESC, ups.AvgScore DESC
LIMIT 50;