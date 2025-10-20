WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC) AS PostRank,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS UserPostRank,
        P.Tags
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS PostCount,
        SUM(Score) AS TotalScore
    FROM 
        Posts
    WHERE 
        PostTypeId IN (1, 2)
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 10 AND SUM(Score) > 100
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    GROUP BY 
        T.TagName
    HAVING 
        COUNT(P.Id) > 5
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS VoteCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
PostHistorySummary AS (
    SELECT 
        PostId,
        COUNT(Id) AS EditCount,
        MAX(CASE WHEN PostHistoryTypeId IN (10, 11) THEN CreationDate END) AS LastEditStatusChange
    FROM 
        PostHistory
    GROUP BY 
        PostId
),
-- Normalize tags into rows in a dialect-neutral way using standard SQL string functions
PostTags AS (
    SELECT
        rp.Id AS PostId,
        TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM t.tag)) AS TagName
    FROM RankedPosts rp
    CROSS JOIN LATERAL (
        WITH RECURSIVE split(rest, value) AS (
            SELECT
                CASE WHEN rp.Tags IS NULL THEN '' ELSE rp.Tags END AS rest,
                NULL::text AS value
            UNION ALL
            SELECT
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                    ELSE ''
                END,
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
                    ELSE rest
                END
            FROM split
            WHERE rest <> ''
        )
        SELECT value AS tag FROM split WHERE value IS NOT NULL AND value <> ''
    ) t
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    U2.DisplayName,
    RP.Reputation,
    RP.PostRank,
    RP.UserPostRank,
    PT.TagName,
    TS.PostCount AS TagPostCount,
    TS.AvgScore AS TagAvgScore,
    UA.PostCount AS UserPostCount,
    UA.CommentCount,
    UA.VoteCount,
    PHS.EditCount,
    PHS.LastEditStatusChange
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
JOIN 
    PostTags PT ON RP.Id = PT.PostId
JOIN 
    TagStats TS ON PT.TagName = TS.TagName
JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN
    Users U2 ON RP.OwnerUserId = U2.Id
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;