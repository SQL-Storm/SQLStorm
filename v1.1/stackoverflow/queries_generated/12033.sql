-- {"query": "12033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 1017} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS UserRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC) AS ScoreRank,
        NTILE(4) OVER (ORDER BY P.CreationDate) AS Quartile
    FROM 
        Posts P
    LEFT JOIN 
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
        RankedPosts
    WHERE 
        UserRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1
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
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
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
        P.Id,
        P.PostTypeId,
        COUNT(PH.Id) AS HistoryCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY 
        P.Id, P.PostTypeId
),
ComplexPredicates AS (
    SELECT 
        P.Id,
        P.Title,
        P.Tags,
        P.Score,
        P.ViewCount,
        LENGTH(P.Body) AS BodyLength,
        CASE 
            WHEN P.Score > 100 THEN 'High Score'
            WHEN P.Score BETWEEN 50 AND 100 THEN 'Medium Score'
            ELSE 'Low Score'
        END AS ScoreCategory,
        COALESCE(U.Reputation, 0) AS UserReputation
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.CreationDate > CURRENT_DATE - INTERVAL '1 year' 
        AND (P.Tags LIKE '%sql%' OR P.Tags LIKE '%database%')
),
FinalQuery AS (
    SELECT 
        RP.Id,
        RP.PostTypeId,
        RP.CreationDate,
        RP.Score,
        RP.ViewCount,
        RP.OwnerUserId,
        RP.OwnerDisplayName,
        RP.UserRank,
        RP.ScoreRank,
        RP.Quartile,
        UA.PostCount AS UserPostCount,
        UA.CommentCount AS UserCommentCount,
        UA.UpVoteCount AS UserUpVoteCount,
        UA.DownVoteCount AS UserDownVoteCount,
        PHS.HistoryCount,
        PHS.LastEditDate,
        CP.ScoreCategory,
        CP.UserReputation
    FROM 
        RankedPosts RP
    JOIN 
        UserActivity UA ON RP.OwnerUserId = UA.Id
    LEFT JOIN 
        PostHistorySummary PHS ON RP.Id = PHS.Id
    LEFT JOIN 
        ComplexPredicates CP ON RP.Id = CP.Id
    WHERE 
        RP.ScoreRank <= 100
        AND RP.Quartile = 1
        AND CP.BodyLength > 1000
        AND CP.UserReputation > 1000
)
SELECT 
    *
FROM 
    FinalQuery
ORDER BY 
    Score DESC, CreationDate;
