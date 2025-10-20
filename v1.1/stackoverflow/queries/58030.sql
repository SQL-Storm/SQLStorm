WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id END) AS Edits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS Closures
    FROM 
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Comments c ON u.Id = c.UserId
        LEFT JOIN Votes v ON p.Id = v.PostId
        LEFT JOIN Badges b ON u.Id = b.UserId
        LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.Reputation
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.Upvotes,
    ua.Downvotes,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.Edits,
    ua.Closures,
    (SELECT AVG(TotalPosts) FROM UserActivity) AS AvgPosts,
    RANK() OVER (ORDER BY ua.TotalPosts DESC, ua.Reputation DESC) AS ActivityRank
FROM 
    UserActivity ua
WHERE 
    ua.TotalPosts > (SELECT AVG(TotalPosts) FROM UserActivity)
    OR ua.Upvotes > (SELECT AVG(Upvotes) FROM UserActivity)
ORDER BY 
    ActivityRank, ua.Reputation DESC
LIMIT 100;