WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.LastActivityDate,
        P.Tags,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC) AS ScoreRank,
        NTILE(4) OVER (ORDER BY P.ViewCount DESC) AS ViewQuartile
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND
        P.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
), 
TagCounts AS (
    SELECT 
        TRIM(value) AS Tag,
        COUNT(*) AS TagCount
    FROM 
        Posts T,
        UNNEST(string_to_array(T.Tags, '<')) AS value
    WHERE 
        T.PostTypeId = 1
    GROUP BY 
        TRIM(value)
), 
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore,
        MAX(P.CreationDate) AS LastPostDate
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.CreationDate >= DATE '2024-10-01' - INTERVAL '1 year'
    GROUP BY 
        U.Id, U.DisplayName
), 
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (2, 5) THEN 1 END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS CloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS ReopenDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
), 
PostVotes AS (
    SELECT 
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Votes V
    GROUP BY 
        V.PostId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.LastActivityDate,
    RP.Tags,
    RP.UserRank,
    RP.ScoreRank,
    RP.ViewQuartile,
    TC.Tag,
    TC.TagCount,
    UA.PostCount,
    UA.TotalScore,
    UA.AvgScore,
    UA.LastPostDate,
    PHS.EditCount,
    PHS.CloseDate,
    PHS.ReopenDate,
    PV.UpVotes,
    PV.DownVotes
FROM 
    RankedPosts RP
LEFT JOIN 
    TagCounts TC ON RP.Tags LIKE '%' || TC.Tag || '%'
LEFT JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    PostVotes PV ON RP.Id = PV.PostId
WHERE 
    RP.ScoreRank <= 100 AND
    RP.ViewQuartile = 1 AND
    (TC.TagCount IS NULL OR TC.TagCount > 100) AND
    (UA.PostCount IS NULL OR UA.PostCount > 5) AND
    (PHS.EditCount IS NULL OR PHS.EditCount > 3)
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;