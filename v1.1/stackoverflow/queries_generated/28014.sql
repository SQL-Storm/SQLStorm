-- {"query": "28014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 3342} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        RANK() OVER (ORDER BY (u.UpVotes - u.DownVotes) DESC) AS EngagementRank,
        AVG(LENGTH(p.Body)) OVER (PARTITION BY u.Id) AS AvgPostLength
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
), PostLifecycle AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        MIN(ph.CreationDate) AS FirstEditTime,
        MAX(ph.CreationDate) AS LastEditTime,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS SubstantialEdits,
        LEAD(p.ClosedDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostClosedDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
)
SELECT
    u.Id,
    u.DisplayName,
    COALESCE(us.GoldBadges, 0) + COALESCE(us.SilverBadges, 0) * 0.5 AS BadgeScore,
    (EXP(us.EngagementRank * -0.001) * 1000)::DECIMAL(10,2) AS DecayedRank,
    pl.SubstantialEdits,
    EXTRACT(EPOCH FROM (pl.LastEditTime - pl.FirstEditTime)) / 3600 AS EditWindowHours,
    (SELECT STRING_AGG(DISTINCT SUBSTRING(t.TagName FROM 1 FOR 3), ';')
     FROM Posts p2
     CROSS JOIN LATERAL unnest(string_to_array(substring(p2.Tags FROM 2 FOR length(p2.Tags)-2), '><')) AS t(TagName)
     WHERE p2.OwnerUserId = u.Id) AS TagPrefixes,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2 
                     INTERSECT 
                     SELECT 1 FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3)
        THEN 'Controversial' 
        ELSE 'Neutral' 
    END AS VotingProfile,
    COALESCE((
        SELECT SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE -1 END)
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (10,11)
    ), 0) AS CloseReopenBalance,
    (SELECT COUNT(*) 
     FROM PostLinks pl2 
     WHERE pl2.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) 
       AND pl2.LinkTypeId = 3) AS DuplicateLinksCreated,
    CORR(us.AvgPostLength, LENGTH(c.Text)) OVER () AS PostCommentLengthCorrelation
FROM Users u
JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN PostLifecycle pl ON u.Id = pl.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
WHERE u.Reputation > 1000
  AND (pl.NextPostClosedDate IS NOT NULL OR u.WebsiteUrl ~ 'https?://[^/]*github\.com')
  AND (u.Location ILIKE '%USA%' OR u.Location IS NULL)
GROUP BY u.Id, u.DisplayName, us.GoldBadges, us.SilverBadges, us.EngagementRank, 
         pl.SubstantialEdits, pl.FirstEditTime, pl.LastEditTime, us.AvgPostLength
HAVING COUNT(DISTINCT pl.PostId) > 10
ORDER BY BadgeScore DESC, DecayedRank ASC
LIMIT 50;
