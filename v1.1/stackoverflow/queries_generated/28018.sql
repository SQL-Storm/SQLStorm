-- {"query": "28018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1507} 

WITH UserBadgeSummary AS (
    SELECT 
        UserId, 
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges 
    GROUP BY UserId
), PostStats AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank,
        COALESCE(NULLIF(p.Tags, ''), 'untagged') AS ProcessedTags
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(u.Location, 'Unknown') AS Location,
    (SELECT MAX(CreationDate) FROM Comments c WHERE c.UserId = u.Id) AS LastCommentDate,
    bs.GoldBadges,
    bs.SilverBadges,
    ps.PostId,
    ps.Upvotes * 10 - ps.Downvotes * 5 AS PostScore,
    STRING_AGG(DISTINCT SUBSTRING(ps.ProcessedTags FROM 2 FOR 5), ', ') AS TagPrefixes,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.PostId = ps.PostId 
        AND ph.PostHistoryTypeId IN (10,11)
        AND ph.CreationDate > '2020-01-01'
    ) AS RecentClosureAttempts
FROM Users u
LEFT JOIN UserBadgeSummary bs ON u.Id = bs.UserId
LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId AND ps.PostRank <= 3
WHERE u.Reputation > 1000
    AND EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
            AND p2.CreationDate BETWEEN '2015-01-01' AND '2023-12-31'
            AND ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p2.Tags FROM 2 FOR LENGTH(p2.Tags)-2), '><'), 1) > 3
    )
GROUP BY u.Id, u.DisplayName, u.Location, bs.GoldBadges, bs.SilverBadges, ps.PostId, ps.Upvotes, ps.Downvotes
HAVING COUNT(ps.PostId) > 1
    OR MAX(ps.Upvotes) > 50
UNION
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    'Duplicate Handler' AS Location,
    NULL AS LastCommentDate,
    0 AS GoldBadges,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.LinkTypeId = 3 AND pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) AS SilverBadges,
    NULL AS PostId,
    NULL AS PostScore,
    NULL AS TagPrefixes,
    NULL AS RecentClosureAttempts
FROM Users u
WHERE EXISTS (
    SELECT 1 
    FROM PostLinks pl 
    WHERE pl.LinkTypeId = 3 
        AND pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
)
EXCEPT
SELECT 
    UserId,
    DisplayName,
    Location,
    LastCommentDate,
    GoldBadges,
    SilverBadges,
    PostId,
    PostScore,
    TagPrefixes,
    RecentClosureAttempts
FROM (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Location,
        NULL AS LastCommentDate,
        0 AS GoldBadges,
        0 AS SilverBadges,
        NULL AS PostId,
        NULL AS PostScore,
        NULL AS TagPrefixes,
        NULL AS RecentClosureAttempts
    FROM Users u
    WHERE u.Reputation < 5000
        AND u.CreationDate < '2010-01-01'
) AS LegacyUsers
ORDER BY UserId DESC, PostScore ASC
LIMIT 1000;
