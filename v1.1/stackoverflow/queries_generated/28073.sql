-- {"query": "28073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1530} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreated,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2, 8)) AS UpVotes,
        COUNT(DISTINCT c.Id) AS TotalComments,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
    GROUP BY u.Id
),
PostStats AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        COALESCE(NULLIF(p.Tags, ''), 'untagged') AS ProcessedTags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS DirectCommentCount,
        AVG(c.Score) OVER (PARTITION BY p.PostTypeId) AS AvgCommentScoreByType,
        SUM(v.BountyAmount) OVER (PARTITION BY p.OwnerUserId) AS TotalBountyByUser
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.TotalBadges,
    ps.PostId,
    ps.Score AS PostScore,
    ps.TotalBountyByUser,
    array_length(string_to_array(ps.ProcessedTags, '><'), 1) AS TagCount,
    (ua.UpVotes * 0.5 + ps.Score * 1.2 + ua.TotalComments * 0.3) AS ActivityIndex,
    (SELECT Name FROM Badges WHERE UserId = ua.UserId ORDER BY Date DESC LIMIT 1) AS LatestBadge,
    CASE 
        WHEN ph.PostHistoryTypeId = 10 THEN (SELECT Name FROM CloseReasonTypes WHERE Id = ph.Comment::int)
        WHEN ph.PostHistoryTypeId IN (33,34) THEN (SELECT Name FROM PostNotices WHERE Id = ph.Comment::int)
        ELSE 'N/A'
    END AS HistoryContext,
    LEAD(ps.CreationDate) OVER (PARTITION BY ua.UserId ORDER BY ps.CreationDate) AS NextPostDate
FROM UserActivity ua
LEFT JOIN PostStats ps ON ua.UserId = ps.OwnerUserId
LEFT JOIN PostHistory ph ON ps.PostId = ph.PostId AND ph.PostHistoryTypeId IN (10, 33, 34)
LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges 
    FROM Badges 
    WHERE Class = 1 
    GROUP BY UserId
) gb ON ua.UserId = gb.UserId
WHERE ua.Reputation > 1000
    AND (ps.ViewCount > 100 OR ps.AnswerCount > 5)
    AND EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = ua.UserId 
        AND p2.PostTypeId = 1 
        AND p2.AcceptedAnswerId IS NOT NULL
    )
GROUP BY 
    ua.UserId, ua.Reputation, ua.TotalBadges, ps.PostId, ps.Score, 
    ps.TotalBountyByUser, ps.ProcessedTags, ph.PostHistoryTypeId, ph.Comment, 
    ua.UpVotes, ua.TotalComments, ps.CreationDate
HAVING COUNT(ps.PostId) > 1 OR MAX(gb.GoldBadges) >= 3
ORDER BY 
    ActivityIndex DESC, 
    ReputationRank ASC 
LIMIT 500;
