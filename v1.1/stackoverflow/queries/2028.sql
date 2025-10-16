WITH RecentActiveUsers AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY P.LastActivityDate DESC) AS rn
    FROM 
        Users U
    INNER JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        U.LastAccessDate > CAST('2024-10-01' AS DATE) - INTERVAL '30 days'
),
UserBadgeCounts AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
UserVoteStats AS (
    SELECT
        V.UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCount
    FROM 
        Votes V
    GROUP BY 
        V.UserId
),
PostTagUsage AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(t.tag_name) AS TotalTagsUsed,
        ARRAY_AGG(t.tag_name) AS AllTags
    FROM
        Posts P
    LEFT JOIN LATERAL (
        SELECT TRIM(tag_name) AS tag_name
        FROM (
            WITH RECURSIVE split(pos, rest) AS (
                SELECT 1, 
                       CASE 
                         WHEN LENGTH(P.Tags) >= 2 THEN SUBSTR(P.Tags, 2, LENGTH(P.Tags) - 2)
                         ELSE '' 
                       END
                UNION ALL
                SELECT
                    (POSITION('><' IN rest) + 3),
                    CASE
                        WHEN POSITION('><' IN rest) = 0 THEN ''
                        ELSE SUBSTR(rest, POSITION('><' IN rest) + 2)
                    END
                FROM split
                WHERE rest <> '' AND POSITION('><' IN rest) > 0
            ),
            parts AS (
                SELECT
                    CASE
                        WHEN POSITION('><' IN rest) = 0 THEN rest
                        ELSE SUBSTR(rest, 1, POSITION('><' IN rest) - 1)
                    END AS tag_name
                FROM split
                WHERE rest <> ''
            )
            SELECT tag_name FROM parts
        )
    ) AS t ON TRUE
    LEFT JOIN 
        Tags TT ON t.tag_name = TT.TagName
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.OwnerUserId
)
SELECT 
    RU.UserId,
    RU.DisplayName,
    RU.Reputation,
    COALESCE(UBC.GoldBadgeCount, 0) AS GoldBadges,
    COALESCE(UBC.SilverBadgeCount, 0) AS SilverBadges,
    COALESCE(UBC.BronzeBadgeCount, 0) AS BronzeBadges,
    COALESCE(UVS.UpvotesCount, 0) AS Upvotes,
    COALESCE(UVS.DownvotesCount, 0) AS Downvotes,
    COALESCE(PTU.TotalTagsUsed, 0) AS TotalTagsUsed,
    PTU.AllTags,
    RU.rn
FROM 
    RecentActiveUsers RU
LEFT JOIN 
    UserBadgeCounts UBC ON RU.UserId = UBC.UserId
LEFT JOIN 
    UserVoteStats UVS ON RU.UserId = UVS.UserId
LEFT JOIN 
    PostTagUsage PTU ON RU.UserId = PTU.UserId
WHERE 
    RU.rn = 1
GROUP BY
    RU.UserId,
    RU.DisplayName,
    RU.Reputation,
    UBC.GoldBadgeCount,
    UBC.SilverBadgeCount,
    UBC.BronzeBadgeCount,
    UVS.UpvotesCount,
    UVS.DownvotesCount,
    PTU.TotalTagsUsed,
    PTU.AllTags,
    RU.rn
ORDER BY 
    RU.Reputation DESC, RU.DisplayName;