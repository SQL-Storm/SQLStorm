-- {"query": "2028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 612} 

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
        U.LastAccessDate > CURRENT_DATE - INTERVAL '30 days'
),
UserBadgeCounts AS (
    SELECT
        B.UserId,
        COUNT(*) FILTER (WHERE B.Class = 1) AS GoldBadgeCount,
        COUNT(*) FILTER (WHERE B.Class = 2) AS SilverBadgeCount,
        COUNT(*) FILTER (WHERE B.Class = 3) AS BronzeBadgeCount
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
        COUNT(TT.TagName) AS TotalTagsUsed,
        array_agg(TT.TagName) AS AllTags
    FROM
        Posts P
    LEFT JOIN 
        unnest(string_to_array(substring(P.Tags from 2 for char_length(P.Tags) - 2), '><')) AS t(tag_name) ON TRUE
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
    PTU.AllTags
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
ORDER BY 
    RU.Reputation DESC, RU.DisplayName;
