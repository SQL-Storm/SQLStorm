-- {"query": "28097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1364} 

WITH UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        MAX(p.Score) AS HighestPostScore,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS ReputationRank,
        CASE 
            WHEN u.Reputation >= 100000 THEN 'Legendary'
            WHEN u.Reputation BETWEEN 50000 AND 99999 THEN 'Epic'
            WHEN u.Reputation BETWEEN 20000 AND 49999 THEN 'Mythic'
            ELSE 'Common'
        END AS ReputationTier
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate > '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.CreationDate, b.Class
),
PostAnalysis AS (
    SELECT 
        p.OwnerUserId,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2), ', ') AS FirstTags,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseEvents,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId, p.Id
)
SELECT 
    ua.*,
    pa.AvgQuestionScore,
    pa.FirstTags,
    pa.CloseEvents,
    COALESCE(pa.NextPostDate - ua.CreationDate, INTERVAL '0 days') AS TimeToNextPost,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.Id AND c.Score > 5) AS HighScoreComments,
    (SELECT SUM(LENGTH(c.Text)) FROM Comments c WHERE c.UserId = ua.Id) AS TotalCommentChars,
    ROUND(ua.UpVotes * 1.0 / NULLIF(ua.DownVotes, 0), 2) AS VoteRatio,
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ua.Id) AND pl.LinkTypeId = 3) AS HasDuplicateLinks
FROM UserActivity ua
LEFT JOIN PostAnalysis pa ON ua.Id = pa.OwnerUserId
WHERE ua.BadgeCount > (SELECT AVG(BadgeCount) FROM UserActivity)
    AND (ua.ReputationTier IN ('Legendary', 'Epic') OR ua.HighestPostScore > 1000)
    AND (pa.CloseEvents < 5 OR pa.CloseEvents IS NULL)
ORDER BY 
    ua.ReputationRank,
    ua.Reputation DESC,
    pa.AvgQuestionScore DESC NULLS LAST
LIMIT 100;
