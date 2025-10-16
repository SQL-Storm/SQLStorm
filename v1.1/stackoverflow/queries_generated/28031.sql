-- {"query": "28031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1570} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    GROUP BY u.Id
),
RankedUsers AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        u.UpVotes,
        u.DownVotes,
        us.TotalPosts,
        us.TotalBadges,
        us.TotalComments,
        us.AvgQuestionScore,
        us.ClosedPosts,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS ClassRank,
        LEAD(u.Id, 1) OVER (ORDER BY u.Reputation DESC) AS NextUserId,
        COALESCE(STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '; '), '') AS TagHistory
    FROM Users u
    LEFT JOIN UserStats us ON u.Id = us.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1,2,3)
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    WHERE u.LastAccessDate > CURRENT_DATE - INTERVAL '1 YEAR'
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, us.TotalPosts, 
             us.TotalBadges, us.TotalComments, us.AvgQuestionScore, us.ClosedPosts, b.Class
)
SELECT 
    ru.Id,
    ru.Reputation,
    ru.ClassRank,
    (ru.UpVotes - ru.DownVotes) * 1.0 / NULLIF(ru.UpVotes + ru.DownVotes, 0) AS VoteRatio,
    ru.TagHistory,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = ru.Id 
       AND p2.ClosedDate IS NOT NULL 
       AND EXISTS (
           SELECT 1 
           FROM PostHistory ph2 
           WHERE ph2.PostId = p2.Id 
             AND ph2.PostHistoryTypeId = 10 
             AND ph2.CreationDate > CURRENT_DATE - INTERVAL '6 MONTHS'
       )) AS RecentClosedPosts,
    COALESCE((
        SELECT SUM(v.BountyAmount) 
        FROM Votes v 
        WHERE v.UserId = ru.Id 
          AND v.VoteTypeId = 8
    ), 0) AS TotalBountySpent,
    DATE_PART('day', CURRENT_DATE - ru.CreationDate) AS DaysSinceJoin,
    ru.NextUserId,
    (SELECT COUNT(DISTINCT RelatedPostId) 
     FROM PostLinks pl 
     WHERE pl.PostId IN (
         SELECT Id 
         FROM Posts 
         WHERE OwnerUserId = ru.Id
     ) AND pl.LinkTypeId = 3
    ) AS DuplicateReferences
FROM RankedUsers ru
WHERE ru.TotalPosts > 10
  AND ru.TotalBadges BETWEEN 5 AND 100
  AND ru.AvgQuestionScore < 15
  AND ru.ClosedPosts > (SELECT AVG(ClosedPosts) FROM UserStats)
  AND EXISTS (
      SELECT 1 
      FROM Posts p3 
      WHERE p3.OwnerUserId = ru.Id 
        AND p3.PostTypeId = 2 
        AND p3.Score > 50
  )
ORDER BY ru.Reputation DESC, ru.ClassRank
LIMIT 100;
