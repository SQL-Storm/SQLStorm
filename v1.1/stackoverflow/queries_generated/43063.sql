-- {"query": "43063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 536} 

WITH UserActivity AS (
    SELECT u.Id, u.DisplayName, COUNT(DISTINCT p.Id) AS TotalPosts, COUNT(DISTINCT b.Id) AS TotalBadges,
           SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS Edits,
           SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN LENGTH(ph.Text) ELSE 0 END) AS TotalEditedTextLength,
           SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseVotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.LastAccessDate >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 year')
    GROUP BY u.Id
),
PostMetrics AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.ViewCount, p.Score, p.CreationDate, 
           COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts,
           COUNT(DISTINCT c.Id) AS TotalComments,
           AVG(c.Score) AS AverageCommentScore
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '6 months')
    GROUP BY p.Id
)
SELECT ua.DisplayName, ua.TotalPosts, ua.TotalBadges, ua.Edits, ua.TotalEditedTextLength, ua.TotalCloseVotes,
       pm.Title, pm.ViewCount, pm.Score, pm.LinkedPosts, pm.TotalComments, pm.AverageCommentScore,
       RANK() OVER (ORDER BY pm.Score DESC, ua.Edits DESC) AS UserPostRank
FROM UserActivity ua
JOIN PostMetrics pm ON ua.Id = pm.OwnerUserId
WHERE pm.TotalComments > 0
ORDER BY UserPostRank, pm.CreationDate DESC
LIMIT 100;
