WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT b.Id) AS GoldBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 10000
      AND p.CreationDate BETWEEN DATE '2022-01-01' AND DATE '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
)
SELECT 
    au.DisplayName,
    au.Reputation,
    au.GoldBadges,
    au.TotalPosts,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    SUM(COALESCE(v.Upvotes, 0)) AS TotalUpvotes,
    SUM(COALESCE(v.Downvotes, 0)) AS TotalDownvotes,
    COUNT(DISTINCT ph.PostId) AS EditedPosts,
    COUNT(DISTINCT pl.RelatedPostId) AS DuplicateLinks
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
LEFT JOIN (
    SELECT 
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes
    GROUP BY PostId
) v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 6, 7)
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
WHERE p.PostTypeId IN (1, 2)
  AND p.Tags LIKE '%<sql>%'
GROUP BY au.DisplayName, au.Reputation, au.GoldBadges, au.TotalPosts, au.Id
ORDER BY (SUM(COALESCE(v.Upvotes, 0)) - SUM(COALESCE(v.Downvotes, 0))) * au.Reputation DESC
LIMIT 100;