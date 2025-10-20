WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.tag AS TagName, 
        COUNT(*) AS TagPostCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM 
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        JOIN LATERAL (
            WITH RECURSIVE split(tag, rest) AS (
                SELECT 
                    NULL AS tag,
                    CASE WHEN p.Tags IS NULL THEN '' ELSE p.Tags END AS rest
                UNION ALL
                SELECT
                    SUBSTRING(rest FROM 2 FOR (CASE WHEN POSITION('>' IN rest) = 0 THEN CHAR_LENGTH(rest) ELSE POSITION('>' IN rest)-2 END)),
                    CASE 
                        WHEN POSITION('>' IN rest) = 0 THEN '' 
                        ELSE SUBSTRING(rest FROM POSITION('>' IN rest)+1)
                    END
                FROM split
                WHERE rest <> ''
            )
            SELECT tag FROM split WHERE tag IS NOT NULL
        ) t ON true
        JOIN Tags tg ON t.tag = tg.TagName
    WHERE 
        p.PostTypeId = 1 
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, t.tag
), TopExpertUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        MAX(TagPostCount) AS MaxTagPostCount,
        STRING_AGG(TagName, ', ' ORDER BY TagPostCount DESC) AS TopTags
    FROM 
        ActiveUserTags
    WHERE 
        TagRank <= 3
    GROUP BY 
        UserId, DisplayName
)
SELECT 
    e.UserId,
    e.DisplayName,
    e.TopTags,
    e.MaxTagPostCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = e.UserId AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = e.UserId AND b.Class = 1) AS GoldBadgeCount
FROM 
    TopExpertUsers e
WHERE 
    e.MaxTagPostCount > 10
ORDER BY 
    e.MaxTagPostCount DESC, 
    UpVoteCount DESC
LIMIT 100;