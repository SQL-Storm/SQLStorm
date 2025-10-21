-- {"query": "28078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1616} 
WITH user_badges AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
), post_stats AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostTypeRank,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeSnippets
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate > '2020-01-01'
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.Body, p.AcceptedAnswerId
)
SELECT 
    u.Id AS UserId,
    CONCAT(u.DisplayName, ' (', COALESCE(u.Location, 'Unknown'), ')') AS UserInfo,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ps.PostId,
    pt.Name AS PostType,
    ps.PostTypeRank,
    (ps.Upvotes - ps.Downvotes) * u.Reputation / 1000.0 AS WeightedEngagement,
    COALESCE((
        SELECT COUNT(*) 
        FROM Posts a 
        WHERE a.ParentId = ps.PostId 
        AND a.Id = ps.AcceptedAnswerId
    ), 0) AS AcceptedAnswers,
    ps.CodeSnippets,
    COALESCE((
        SELECT MAX(c.CreationDate)
        FROM Comments c
        WHERE c.PostId = ps.PostId
        AND c.UserId = u.Id
    ), u.CreationDate) AS LastInteraction,
    CASE 
        WHEN u.DownVotes > 0 THEN (u.UpVotes * 1.0 / NULLIF(u.DownVotes, 0)) 
        ELSE u.UpVotes 
    END AS UpDownRatio,
    SUBSTRING(COALESCE(u.AboutMe, 'No bio'), 1, 50) AS BioPreview
FROM Users u
LEFT JOIN user_badges ub ON u.Id = ub.UserId
LEFT JOIN post_stats ps ON u.Id = ps.OwnerUserId
LEFT JOIN PostTypes pt ON ps.PostTypeId = pt.Id
WHERE u.Reputation > 1000
  AND EXISTS (
    SELECT 1
    FROM Posts p2
    WHERE p2.OwnerUserId = u.Id
    AND p2.Tags LIKE '%<sql>%'
  )
  AND u.Id IN (
    SELECT UserId FROM Badges WHERE Name LIKE '%Moderator%'
    INTERSECT
    SELECT UserId FROM PostHistory WHERE PostHistoryTypeId = 6
  )
ORDER BY 
    u.Reputation DESC,
    WeightedEngagement DESC,
    LastInteraction DESC
LIMIT 100;