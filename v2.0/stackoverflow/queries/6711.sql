-- {"query": "6711.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 632}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
RecentVotes AS (
    SELECT 
        V.PostId,
        V.UserId,
        COUNT(V.Id) AS VoteCount,
        MAX(V.CreationDate) AS LastVoteDate
    FROM 
        Votes V
    WHERE 
        V.VoteTypeId IN (2, 3) AND V.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
    GROUP BY 
        V.PostId, V.UserId
),
PostTags AS (
    -- Normalize tag list from Posts.Tags which is assumed to be a string like "<tag1><tag2>"
    SELECT
        P.Id AS PostId,
        TRIM(BOTH '>' FROM TAG) AS TagName
    FROM
        Posts P
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(COALESCE(P.Tags, ''), '><') AS TAG
        ) s
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName,
    U.Reputation,
    COALESCE(B.BadgeCount, 0) AS BadgeCount,
    COALESCE(RV.VoteCount, 0) AS VoteCount,
    RV.LastVoteDate,
    STRING_AGG(DISTINCT PT.TagName, ', ' ORDER BY PT.TagName) AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    RecentVotes RV ON RP.Id = RV.PostId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    PostTags PT ON P.Id = PT.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, RP.OwnerUserId,
    U.DisplayName, U.Reputation, B.BadgeCount, RV.VoteCount, RV.LastVoteDate
ORDER BY 
    RP.Rank, RP.Score DESC, RP.ViewCount DESC;