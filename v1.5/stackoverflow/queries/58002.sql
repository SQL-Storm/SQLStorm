-- {"query": "58002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1166} 
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
      AND p.CreationDate BETWEEN '2022-01-01' AND '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
)
SELECT 
    au.DisplayName,
    au.Reputation,
    au.GoldBadges,
    au.TotalPosts,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    SUM(v.Upvotes) AS TotalUpvotes,
    SUM(v.Downvotes) AS TotalDownvotes,
    COUNT(DISTINCT ph.PostId) AS EditedPosts,
    COUNT(DISTINCT pl.RelatedPostId) AS DuplicateLinks
FROM ActiveUsers au
JOIN Posts p ON au.Id = p.OwnerUserId
LEFT JOIN (
    SELECT 
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS Downvotes
    FROM Votes
    GROUP BY PostId
) v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 6, 7)
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
WHERE p.PostTypeId IN (1, 2)
  AND p.Tags LIKE '%<sql>%'
GROUP BY au.DisplayName, au.Reputation, au.GoldBadges, au.TotalPosts
ORDER BY (TotalUpvotes - TotalDownvotes) * au.Reputation DESC
LIMIT 100;