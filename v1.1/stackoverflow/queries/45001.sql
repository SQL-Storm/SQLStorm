WITH UserStats AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.Reputation
), 
TagPopularity AS (
    SELECT 
        tag AS TagName,
        COUNT(*) AS TagFrequency,
        AVG(Score) AS AvgTagScore
    FROM (
        SELECT
            p.*,
            TRIM(tag_piece) AS tag
        FROM Posts p,
        LATERAL (
            SELECT regexp_split_to_table(
                SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)),
                '><'
            ) AS tag_piece
        ) s
        WHERE p.PostTypeId = 1
    ) sub
    GROUP BY 
        tag
)
SELECT 
    us.UserId,
    us.Reputation,
    us.PostCount,
    us.VoteCount,
    us.AvgPostScore,
    tp.TagName,
    tp.TagFrequency,
    tp.AvgTagScore
FROM 
    UserStats us
JOIN 
    TagPopularity tp ON tp.TagFrequency > 50
ORDER BY 
    us.Reputation DESC, 
    us.PostCount DESC
LIMIT 100;