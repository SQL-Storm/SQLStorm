-- {"query": "28001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1583} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        (u.UpVotes * 1.0 / NULLIF(u.UpVotes + u.DownVotes, 0)) AS ScoreRatio,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
    HAVING COUNT(b.Id) > 5
),
PostStats AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.Title,
        p.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > '2020-01-01'
      AND LEFT(p.Title, 3) = 'How'
),
CloseReasons AS (
    SELECT 
        ph.PostId,
        crt.Name AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS Rn
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    WHERE ph.PostHistoryTypeId = 10
)
SELECT 
    au.DisplayName,
    au.ScoreRatio,
    ps.Title,
    STRING_AGG(DISTINCT SUBSTRING(ps.Tags, 2, LENGTH(ps.Tags)-2), '|') AS CleanedTags,
    cr.CloseReason,
    au.GoldBadges,
    COALESCE(ps.CommentCount, 0) + au.GoldBadges AS EngagementScore,
    CASE 
        WHEN cr.CloseReason IS NULL THEN 'Never Closed' 
        ELSE 'Closed: ' || cr.CloseReason 
    END AS ClosureStatus,
    CONCAT(au.Location, ' - ', COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 20), 'No bio')) AS UserBio
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN CloseReasons cr ON ps.Id = cr.PostId AND cr.Rn = 1
JOIN Users u ON au.Id = u.Id
WHERE au.Reputation > 10000
  AND ps.PostRank = 1
  AND (ps.Score > 50 OR ps.CommentCount > 10)
  AND EXTRACT(YEAR FROM u.CreationDate) BETWEEN 2008 AND 2012
UNION
SELECT 
    au.DisplayName,
    au.ScoreRatio,
    NULL,
    NULL,
    NULL,
    au.GoldBadges,
    au.GoldBadges,
    'No Posts',
    CONCAT(au.Location, ' - ', COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 20), 'No bio'))
FROM ActiveUsers au
JOIN Users u ON au.Id = u.Id
WHERE au.Id NOT IN (SELECT OwnerUserId FROM Posts)
  AND au.Reputation > 50000
ORDER BY EngagementScore DESC, GoldBadges DESC, DisplayName
LIMIT 100;
