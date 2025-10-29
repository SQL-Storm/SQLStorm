-- {"query": "6410.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 712}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        P.OwnerUserId,
        U.Reputation,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS ScoreRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId = 1 AND P.ViewCount > 100
    GROUP BY 
        P.Id, P.Title, P.Score, P.ViewCount, P.CreationDate, P.LastActivityDate, U.DisplayName, P.OwnerUserId, U.Reputation
),
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
PostTags AS (
    -- normalize tags string like "<tag1><tag2>" into rows; use a portable approach where possible
    SELECT
        P.Id AS PostId,
        -- replace regexp_split_to_table with a generic split using XML method for compatibility where regexp_split_to_table not available
        TRIM(BOTH '<>' FROM t.tag) AS TagName
    FROM Posts P
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(P.Tags, '><') AS tag
    ) t
    WHERE P.Tags IS NOT NULL
),
TagCounts AS (
    -- count tags per post to allow ordering without nesting aggregates
    SELECT
        PT.PostId,
        PT.TagName,
        COUNT(*) AS TagCount
    FROM PostTags PT
    GROUP BY PT.PostId, PT.TagName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RS.BadgeCount,
    RS.GoldBadgeCount,
    RS.SilverBadgeCount,
    RS.BronzeBadgeCount,
    CASE 
        WHEN RP.ScoreRank <= 10 THEN 'Top Scorer'
        WHEN RP.ScoreRank <= 100 THEN 'Active Contributor'
        ELSE 'Regular Contributor'
    END AS ContributionLevel,
    STRING_AGG(TC.TagName, ', ' ORDER BY TC.TagCount DESC) AS TopTags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary RS ON RP.OwnerUserId = RS.UserId
LEFT JOIN 
    PostTags PT ON RP.Id = PT.PostId
LEFT JOIN
    TagCounts TC ON RP.Id = TC.PostId AND PT.TagName = TC.TagName
LEFT JOIN 
    Tags TagRef ON TC.TagName = TagRef.TagName
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.OwnerDisplayName, RP.Reputation, RS.BadgeCount, RS.GoldBadgeCount, RS.SilverBadgeCount, RS.BronzeBadgeCount, RP.ScoreRank
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;