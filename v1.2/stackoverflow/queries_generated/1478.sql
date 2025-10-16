-- {"query": "1478.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1224} 
WITH RecursiveUserBadgeCTE AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MIN(b.Date)) AS BadgeOrder
    FROM
        Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(b.Id) > 5
),

LatestPostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        COALESCE(ph.LastEditDate, p.LastActivityDate) AS LastActivity,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(p.AcceptedAnswerId, 0) ORDER BY p.Score DESC NULLS LAST) AS ScoreRank
    FROM 
        Posts p
    LEFT JOIN LATERAL (
      SELECT MAX(LastEditDate) AS LastEditDate
      FROM Posts ph2
      WHERE ph2.ParentId = p.ParentId OR ph2.Id = p.Id
    ) ph ON TRUE
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),

FilteredActivePosts AS (
    SELECT p.*
    FROM LatestPostActivity p
    WHERE p.ScoreRank <= 5
),

DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        rk.Name as LinkTypeName
    FROM
        PostLinks pl
    JOIN LinkTypes lk ON lk.Id = pl.LinkTypeId
    JOIN LinkTypes rk ON rk.Id = pl.LinkTypeId
    WHERE
        lk.Name = 'Duplicate'
),

UserRecentBadges AS (
    SELECT DISTINCT ON (UserId) 
        UserId,
        Name AS RecentBadgeName,
        Date AS RecentBadgeDate
    FROM Badges
    ORDER BY UserId, Date DESC
),

AggregatedVotes AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
)

SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    rub.RecentBadgeName,
    rub.RecentBadgeDate,
    bu.TotalBadges,
    bu.GoldBadges,
    bu.SilverBadges,
    bu.BronzeBadges,
    fa.PostId,
    fa.Title,
    fa.Score,
    LENGTH(fa.Tags) - LENGTH(REPLACE(fa.Tags, '><', '')) + 1 AS TagCount,
    av.UpVotes,
    av.DownVotes,
    av.TotalBounty,
    dl.RelatedPostId,
    
    -- Complex derived field: net reputation contributed combining votes and badges weighted differently
    ((COALESCE(av.UpVotes,0) * 10) - (COALESCE(av.DownVotes,0) * 5) + (bu.GoldBadges * 100) + (bu.SilverBadges * 50) + (bu.BronzeBadges * 20)) AS NetReputationImpact,

    -- String and NULL logic construction: DisplayName with badge info (handle if DisplayName NULL)
    CASE 
      WHEN u.DisplayName IS NULL OR u.DisplayName = '' THEN '[Anonymous]'
      ELSE u.DisplayName || ' (Badge: ' || COALESCE(rub.RecentBadgeName, 'None') || ')'
    END AS DisplayNameWithBadge,
    
    -- Correlated subquery to count how many comments user has posted on posts within last year
    (SELECT COUNT(*)
     FROM Comments c 
     WHERE c.UserId = u.Id 
       AND c.CreationDate > NOW() - INTERVAL '12 months') AS CommentsLastYear,

    -- Window function to rank users by reputation, breaking ties by total badges descending
    RANK() OVER (ORDER BY u.Reputation DESC, bu.TotalBadges DESC) AS UserReputationRank

FROM
    Users u
INNER JOIN RecursiveUserBadgeCTE bu ON bu.UserId = u.Id AND bu.BadgeOrder = 1
LEFT JOIN UserRecentBadges rub ON rub.UserId = u.Id
LEFT JOIN FilteredActivePosts fa ON fa.OwnerUserId = u.Id
LEFT JOIN AggregatedVotes av ON av.PostId = fa.PostId
LEFT JOIN DuplicateLinks dl ON dl.PostId = fa.PostId AND dl.RelatedPostId IS NOT NULL

WHERE
    u.Reputation > (
        SELECT AVG(Reputation) 
        FROM Users
    )
    AND (fa.Score > COALESCE((SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId=1), 0) OR fa.PostId IS NULL)
    AND (
      u.Location IS NULL OR
      u.Location NOT IN ('San Francisco', 'New York', 'London')
    )
ORDER BY 
    NetReputationImpact DESC,
    CommentsLastYear DESC
LIMIT 50;