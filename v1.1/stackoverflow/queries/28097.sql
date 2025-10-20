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
    WHERE u.CreationDate > DATE '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.CreationDate, b.Class
),
PostAnalysis AS (
    SELECT 
        p.OwnerUserId,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        STRING_AGG(DISTINCT SUBSTR(p.Tags, 2, (POSITION('>' IN p.Tags) - 2)), ', ') AS FirstTags,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseEvents,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostDate,
        p.Id
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId, p.Id, p.CreationDate, p.Tags, p.PostTypeId, p.Score
)
SELECT 
    ua.Id,
    ua.Reputation,
    ua.CreationDate,
    ua.BadgeCount,
    ua.UpVotes,
    ua.DownVotes,
    ua.HighestPostScore,
    ua.ReputationRank,
    ua.ReputationTier,
    pa.AvgQuestionScore,
    pa.FirstTags,
    pa.CloseEvents,
    COALESCE((pa.NextPostDate - ua.CreationDate), INTERVAL '0 days') AS TimeToNextPost,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.Id AND c.Score > 5) AS HighScoreComments,
    (SELECT SUM(LENGTH(c.Text)) FROM Comments c WHERE c.UserId = ua.Id) AS TotalCommentChars,
    ROUND(ua.UpVotes * 1.0 / NULLIF(ua.DownVotes, 0), 2) AS VoteRatio,
    EXISTS (
        SELECT 1 
        FROM PostLinks pl 
        WHERE pl.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = ua.Id) 
          AND pl.LinkTypeId = 3
    ) AS HasDuplicateLinks
FROM UserActivity ua
LEFT JOIN (
    SELECT OwnerUserId,
           AVG(AvgQuestionScore) AS AvgQuestionScore,
           STRING_AGG(FirstTags, ', ') AS FirstTags,
           SUM(CloseEvents) AS CloseEvents,
           MIN(NextPostDate) AS NextPostDate
    FROM PostAnalysis
    GROUP BY OwnerUserId
) pa ON ua.Id = pa.OwnerUserId
WHERE ua.BadgeCount > (SELECT AVG(BadgeCount) FROM UserActivity)
    AND (ua.ReputationTier IN ('Legendary', 'Epic') OR ua.HighestPostScore > 1000)
    AND (pa.CloseEvents < 5 OR pa.CloseEvents IS NULL)
ORDER BY 
    ua.ReputationRank,
    ua.Reputation DESC,
    pa.AvgQuestionScore DESC
LIMIT 100;