-- {"query": "28007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1593} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserJoinDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS RepRankInClass,
        SUM(COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) OVER (PARTITION BY u.Id ORDER BY u.CreationDate) AS CumulativeVotes
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN (
        SELECT 
            UserId, 
            COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
            COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes
        FROM Votes 
        GROUP BY UserId
    ) v ON u.Id = v.UserId
    WHERE u.LastAccessDate > '2020-01-01' OR u.LastAccessDate IS NULL
    GROUP BY u.Id, b.Class, v.UpVotes, v.DownVotes
),
PostAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        ph.CreationDate AS LastEditDate,
        ph.PostHistoryTypeId,
        LEAD(ph.PostHistoryTypeId) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate) AS NextHistoryType,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ', '), 'Untagged') AS ResolvedTags,
        (SELECT MAX(CreationDate) FROM Comments WHERE PostId = p.Id) AS LastCommentDate,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM PostHistory ph2 
                WHERE ph2.PostId = p.Id 
                AND ph2.PostHistoryTypeId IN (10,11)
            ) THEN 'Controversial' 
            ELSE 'Stable' 
        END AS PostStability
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId BETWEEN 4 AND 9
    LEFT JOIN (
        SELECT Id, UNNEST(STRING_TO_ARRAY(SUBSTRING(Tags, 2, LENGTH(Tags)-2), '><'), NULL)) AS TagName 
        FROM Posts 
        WHERE PostTypeId = 1
    ) t ON p.Id = t.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, ph.CreationDate, ph.PostHistoryTypeId
)
SELECT 
    u.UserId,
    u.RepRankInClass,
    pa.PostId,
    pa.ResolvedTags,
    pa.PostStability,
    (pa.Score * 0.5 + pa.ViewCount * 0.3 + LENGTH(pa.ResolvedTags) * 0.2) AS PostQualityIndex,
    (SELECT COUNT(*) FROM Votes WHERE PostId = pa.PostId AND VoteTypeId = 2) - 
    (SELECT COUNT(*) FROM Votes WHERE PostId = pa.PostId AND VoteTypeId = 3) AS VoteBalance,
    COALESCE((SELECT Text FROM Comments WHERE PostId = pa.PostId ORDER BY CreationDate DESC LIMIT 1), 'No comments') AS LatestComment
FROM UserStats u
JOIN PostAnalysis pa ON u.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pa.PostId)
WHERE u.TotalBadges > (SELECT AVG(TotalBadges) FROM UserStats)
  AND pa.NextHistoryType IS NOT NULL
  AND pa.ResolvedTags LIKE '%sql%'
  AND u.CumulativeVotes > 100
ORDER BY u.Reputation DESC, PostQualityIndex DESC
LIMIT 100;
