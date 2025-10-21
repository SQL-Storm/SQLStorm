-- {"query": "58004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1336} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
      AND u.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.AnswerCount) AS TotalAnswersGenerated,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
      AND p.CreationDate BETWEEN '2015-01-01' AND '2023-12-31'
    GROUP BY p.OwnerUserId
),
HistoryEvents AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS ClosedPosts,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.PostId END) AS ReopenedPosts,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.PostId END) AS SuggestedEditsApplied
    FROM PostHistory ph
    WHERE ph.CreationDate BETWEEN '2018-01-01' AND '2023-12-31'
    GROUP BY ph.UserId
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.GoldBadges,
    au.SilverBadges,
    au.BronzeBadges,
    ps.AvgPostScore,
    ps.TotalViews,
    ps.TotalAnswersGenerated,
    ps.TotalVotes,
    ps.Upvotes,
    ps.Downvotes,
    he.ClosedPosts,
    he.ReopenedPosts,
    he.SuggestedEditsApplied,
    DENSE_RANK() OVER (ORDER BY (au.Reputation + ps.TotalViews + ps.TotalAnswersGenerated) DESC) AS EngagementRank
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN HistoryEvents he ON au.Id = he.UserId
WHERE ps.TotalVotes > 100
  AND au.TotalPosts > 50
ORDER BY 
    EngagementRank,
    au.Reputation DESC,
    ps.TotalViews DESC
LIMIT 100;
