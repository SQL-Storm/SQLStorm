WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM 
        Posts p
    WHERE
        p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
        AND p.Score > 0
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.Reputation
),
TopTags AS (
    SELECT
        tt.Tag,
        COUNT(pt.Id) AS PostCount
    FROM
        Tags t
        JOIN Posts pt ON pt.Tags LIKE '%' || t.TagName || '%'
        CROSS JOIN LATERAL (
            WITH RECURSIVE Split(pos, rest, tag) AS (
                SELECT
                    1 AS pos,
                    CAST(t.TagName AS TEXT) AS rest,
                    CASE WHEN t.TagName = '' THEN NULL
                         WHEN POSITION(',' IN t.TagName) = 0 THEN t.TagName
                         ELSE SUBSTRING(t.TagName FROM 1 FOR POSITION(',' IN t.TagName)-1)
                    END AS tag
                UNION ALL
                SELECT
                    pos + 1,
                    CASE
                        WHEN POSITION(',' IN rest) = 0 THEN ''
                        ELSE SUBSTRING(rest FROM POSITION(',' IN rest)+1)
                    END,
                    CASE
                        WHEN POSITION(',' IN rest) = 0 THEN rest
                        ELSE SUBSTRING(rest FROM 1 FOR POSITION(',' IN rest)-1)
                    END
                FROM Split
                WHERE rest <> '' AND POSITION(',' IN rest) > 0
            )
            SELECT TRIM(tag) AS Tag
            FROM Split
            WHERE tag IS NOT NULL
        ) AS tt
    GROUP BY
        tt.Tag
    HAVING
        COUNT(pt.Id) > 10
),
UserBadges AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ',' ORDER BY b.Date DESC) AS BadgeList
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
MaxTopTagCount AS (
    SELECT MAX(PostCount) AS MaxCount FROM TopTags
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    ur.Reputation,
    ur.PostCount,
    COALESCE(tb.Tag, 'No Tags') AS TopTag,
    ub.BadgeList
FROM 
    RankedPosts rp
JOIN 
    UserReputation ur ON rp.OwnerUserId = ur.UserId
LEFT JOIN 
    TopTags tb ON tb.PostCount = (SELECT MaxCount FROM MaxTopTagCount)
LEFT JOIN 
    UserBadges ub ON ub.UserId = rp.OwnerUserId
WHERE 
    rp.rn = 1
GROUP BY
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    ur.Reputation,
    ur.PostCount,
    tb.Tag,
    ub.BadgeList,
    rp.OwnerUserId,
    rp.rn
ORDER BY 
    rp.Score DESC, ur.Reputation DESC
LIMIT 50;