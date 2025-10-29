-- {"query": "15009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 969}
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostActivityAnalysis AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.CreationDate) AS LatestPostDate,
        SUM(COALESCE(p.CommentCount, 0)) AS TotalComments
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.BadgeCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.BadgeRank,
    pa.TotalPosts,
    pa.AvgPostScore,
    pa.MaxViewCount,
    pa.QuestionCount,
    pa.AnswerCount,
    pa.LatestPostDate,
    pa.TotalComments,
    COALESCE(v.UpvoteCount, 0) AS UpvoteCount,
    COALESCE(v.DownvoteCount, 0) AS DownvoteCount,
    CASE 
        WHEN pa.TotalPosts > 0 THEN 
            ROUND(COALESCE(v.UpvoteCount, 0) * 100.0 / pa.TotalPosts, 2)
        ELSE 0 
    END AS UpvotePerPostRatio,
    DENSE_RANK() OVER (
        ORDER BY 
            (COALESCE(ubs.GoldBadges, 0) * 3 + 
             COALESCE(ubs.SilverBadges, 0) * 2 + 
             COALESCE(ubs.BronzeBadges, 0)) DESC
    ) AS ContributorTier
FROM UserBadgeStats ubs
JOIN PostActivityAnalysis pa ON ubs.UserId = pa.OwnerUserId
LEFT JOIN (
    SELECT 
        UserId, 
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpvoteCount,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownvoteCount
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
) v ON ubs.UserId = v.UserId
WHERE ubs.BadgeCount > 0 
  AND pa.TotalPosts > 10
  AND ubs.DisplayName IS NOT NULL
ORDER BY ContributorTier, ubs.BadgeCount DESC
LIMIT 100;
