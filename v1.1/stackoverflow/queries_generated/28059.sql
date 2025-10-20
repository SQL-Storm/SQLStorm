-- {"query": "28059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1420} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
        ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS ClassRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, b.Class
), PostActivity AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
        STRING_AGG(DISTINCT t.TagName, '; ') FILTER (WHERE p.PostTypeId = 1) AS QuestionTags,
        COALESCE(MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END), 'Never closed') AS CloseReason
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6,10)
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Tags t ON t.TagName = ANY(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '><', ','), '<>', ''), ','))
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.Id, p.OwnerUserId
)
SELECT 
    u.DisplayName,
    u.Reputation,
    us.TotalBadges,
    us.TotalPosts,
    pa.EditCount,
    pa.CommentCount,
    pa.Upvotes - pa.Downvotes AS NetVotes,
    pa.QuestionTags,
    pa.CloseReason,
    (us.AvgQuestionScore * 0.6 + us.AvgAnswerScore * 0.4) AS WeightedScore,
    DATE_PART('day', NOW() - us.LastPostDate) AS DaysSinceLastActivity,
    CASE 
        WHEN u.Reputation > 100000 THEN 'Top Contributor'
        WHEN u.Reputation BETWEEN 50000 AND 100000 THEN 'Active Contributor'
        ELSE 'Regular User'
    END AS ContributorLevel,
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 2 
     AND p2.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2)) AS HighQualityAnswers
FROM Users u
JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN PostActivity pa ON u.Id = pa.OwnerUserId
WHERE u.Reputation > 1000
    AND EXISTS (
        SELECT 1 FROM Votes v2 
        WHERE v2.UserId = u.Id 
        AND v2.VoteTypeId = 8 
        AND v2.BountyAmount > 50
    )
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id 
        AND ph2.PostHistoryTypeId = 12
    )
ORDER BY 
    us.GlobalRank,
    WeightedScore DESC NULLS LAST,
    DaysSinceLastActivity
LIMIT 100;
