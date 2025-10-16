-- {"query": "2036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 744} 

WITH RecentActivity AS (
    SELECT 
        PostId, 
        MAX(CreationDate) AS LastActivityDate
    FROM 
        (SELECT PostId, CreationDate FROM Comments
         UNION ALL
         SELECT PostId, CreationDate FROM Votes
         UNION ALL
         SELECT Id AS PostId, LastEditDate AS CreationDate FROM Posts
         UNION ALL
         SELECT Id AS PostId, LastActivityDate AS CreationDate FROM Posts
         UNION ALL
         SELECT PostId, CreationDate FROM PostHistory) AS CombinedActivity
    GROUP BY PostId
),
UserBadges AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
HighReputationPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.Score >= 10
),
TagStats AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        COUNT(DISTINCT pt.PostId) AS TaggedPostsCount
    FROM 
        Tags t
    LEFT JOIN 
        LATERAL (
            SELECT 
                p.Id AS PostId
            FROM 
                Posts p
            WHERE 
                t.TagName = ANY (string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
        ) pt ON TRUE
    GROUP BY 
        t.Id
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    ha.Title AS TopTitle,
    ha.Score AS TopScore,
    ra.LastActivityDate,
    ts.TagName AS MostUsedTag
FROM 
    Users ua
LEFT JOIN 
    RecentActivity ra ON ra.PostId = (
        SELECT PostId 
        FROM Posts p 
        WHERE p.OwnerUserId = ua.Id 
        ORDER BY ra.LastActivityDate DESC 
        LIMIT 1
    ) 
LEFT JOIN 
    UserBadges ub ON ub.UserId = ua.Id
LEFT JOIN 
    HighReputationPosts ha ON ha.PostRank = 1 AND ha.PostId = (
        SELECT pq.Id 
        FROM Posts pq 
        WHERE pq.OwnerUserId = ua.Id 
        ORDER BY pq.Score DESC 
        LIMIT 1
    ) 
LEFT JOIN 
    TagStats ts ON ts.TagId = (
        SELECT t.Id
        FROM Tags t
        LEFT JOIN Posts p ON t.TagName = ANY (string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
        WHERE p.OwnerUserId = ua.Id
        GROUP BY t.Id
        ORDER BY COUNT(p.Id) DESC
        LIMIT 1
    )
WHERE 
    ua.Reputation > 1000
ORDER BY 
    ua.Reputation DESC
LIMIT 100;
