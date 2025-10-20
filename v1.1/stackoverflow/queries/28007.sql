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
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes 
        GROUP BY UserId
    ) v ON u.Id = v.UserId
    WHERE u.LastAccessDate > DATE '2020-01-01' OR u.LastAccessDate IS NULL
    GROUP BY u.Id, u.Reputation, u.CreationDate, b.Class, v.UpVotes, v.DownVotes
),
PostTags AS (
    SELECT
        p.Id,
        TRIM(tag) AS TagName
    FROM Posts p,
    LATERAL (
        SELECT regexp_split_to_table(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><') AS tag
    ) s
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
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
        COALESCE(STRING_AGG(DISTINCT pt.TagName, ', '), 'Untagged') AS ResolvedTags,
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
    LEFT JOIN PostTags pt ON p.Id = pt.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.Tags, ph.CreationDate, ph.PostHistoryTypeId
)
SELECT 
    u.UserId,
    u.RepRankInClass,
    pa.PostId,
    pa.ResolvedTags,
    pa.PostStability,
    (pa.Score * 0.5 + pa.ViewCount * 0.3 + length(pa.ResolvedTags) * 0.2) AS PostQualityIndex,
    (SELECT COUNT(*) FROM Votes v1 WHERE v1.PostId = pa.PostId AND v1.VoteTypeId = 2) - 
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = pa.PostId AND v2.VoteTypeId = 3) AS VoteBalance,
    COALESCE((SELECT c2.Text FROM Comments c2 WHERE c2.PostId = pa.PostId ORDER BY c2.CreationDate DESC LIMIT 1), 'No comments') AS LatestComment,
    u.Reputation
FROM UserStats u
JOIN PostAnalysis pa ON u.UserId = (
    SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = pa.PostId
)
WHERE u.TotalBadges > (SELECT AVG(us.TotalBadges) FROM UserStats us)
  AND pa.NextHistoryType IS NOT NULL
  AND pa.ResolvedTags LIKE '%sql%'
  AND u.CumulativeVotes > 100
ORDER BY u.Reputation DESC, PostQualityIndex DESC
LIMIT 100;