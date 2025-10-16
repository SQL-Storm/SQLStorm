WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        P.Tags,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) OVER (PARTITION BY P.Id) AS UpVoteCount,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) OVER (PARTITION BY P.Id) AS DownVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY P.OwnerUserId) AS TotalUserUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY P.OwnerUserId) AS TotalUserDownVotes
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS TagUsageCount,
        AVG(P.Score) AS AvgTagScore
    FROM 
        Tags T
    JOIN 
        Posts P ON POSITION('<' || T.TagName || '>' IN P.Tags) > 0
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        MAX(P.CreationDate) AS LatestActivity
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.PostHistoryTypeId) AS HistoryEventCount,
        MAX(PH.CreationDate) AS LastHistoryEventDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.Tags,
    RP.UserPostRank,
    RP.UpVoteCount,
    RP.DownVoteCount,
    RP.TotalUserUpVotes,
    RP.TotalUserDownVotes,
    TS.TagUsageCount,
    TS.AvgTagScore,
    UA.PostCount,
    UA.TotalScore,
    UA.LatestActivity,
    PHS.HistoryEventCount,
    PHS.LastHistoryEventDate
FROM 
    RankedPosts RP
JOIN 
    TagStats TS ON POSITION('<' || TS.TagName || '>' IN RP.Tags) > 0
JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.UserPostRank <= 3
    AND RP.Score > 0
    AND (
        POSITION('<sql>' IN RP.Tags) > 0
        OR
        POSITION('<database>' IN RP.Tags) > 0
    )
    AND (RP.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year'))
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;