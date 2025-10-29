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
    STRING_AGG(T.TagName, ', ') WITHIN GROUP (ORDER BY T.Count DESC) AS TopTags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary RS ON RP.OwnerUserId = RS.UserId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    UNNEST(STRING_TO_ARRAY(P.Tags, '/><')) AS T(TagName) 
LEFT JOIN 
    Tags T ON T.TagName = T.TagName
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.OwnerDisplayName, RP.Reputation, RS.BadgeCount, RS.GoldBadgeCount, RS.SilverBadgeCount, RS.BronzeBadgeCount, RP.ScoreRank
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
