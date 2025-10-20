-- {"query": "58039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1527} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 5, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2, 3)
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50 OR COUNT(c.Id) > 100
),
PostClosures AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseEvents,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenEvents,
        STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasons
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON ph.Comment::INT = crt.Id
    WHERE ph.PostHistoryTypeId IN (10, 11)
    GROUP BY ph.PostId
),
TagUsage AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>')) AS Tag,
        COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
)
SELECT 
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.TotalBadges,
    au.AvgQuestionScore,
    au.AvgAnswerScore,
    COALESCE(SUM(pc.CloseEvents), 0) AS TotalClosures,
    COALESCE(SUM(pc.ReopenEvents), 0) AS TotalReopens,
    (SELECT STRING_AGG(t.Tag || ' (' || t.TagCount || ')', ', ' ORDER BY t.TagCount DESC) 
     FROM TagUsage t 
     WHERE t.OwnerUserId = au.Id AND t.TagCount > 5) AS TopTags,
    RANK() OVER (ORDER BY (au.TotalPosts * 2 + au.TotalComments * 0.5 + au.TotalVotes * 0.1 + au.TotalBadges * 10) DESC) AS ActivityRank
FROM ActiveUsers au
LEFT JOIN Posts p ON au.Id = p.OwnerUserId
LEFT JOIN PostClosures pc ON p.Id = pc.PostId
GROUP BY au.Id, au.DisplayName, au.Reputation, au.TotalPosts, au.TotalComments, au.TotalVotes, au.TotalBadges, au.AvgQuestionScore, au.AvgAnswerScore
ORDER BY ActivityRank, au.Reputation DESC
LIMIT 50;
