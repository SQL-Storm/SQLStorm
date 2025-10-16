WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) OVER (PARTITION BY P.Id) AS UpVotes,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) OVER (PARTITION BY P.Id) AS DownVotes,
        P.OwnerUserId
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        *
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 10
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS TagUsageCount,
        AVG(P.Score) AS AvgTagScore
    FROM 
        Tags T
    JOIN 
        Posts P ON POSITION(('<' || T.TagName || '>') IN P.Tags) > 0
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionCount,
        COUNT(P.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswerCount,
        SUM(P.Score) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestionScore,
        SUM(P.Score) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswerScore
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
CorrelatedSubquery AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = P.Id) AS CommentCount
    FROM 
        Posts P
    WHERE 
        P.PostTypeId IN (1, 2)
),
FinalResult AS (
    SELECT 
        TP.Id,
        TP.PostTypeId,
        TP.CreationDate,
        TP.Score,
        TP.ViewCount,
        TP.Title,
        TP.Tags,
        TP.AnswerCount,
        TP.CommentCount,
        TP.FavoriteCount,
        TP.OwnerDisplayName,
        TP.OwnerReputation,
        TP.PostRank,
        TP.UpVotes,
        TP.DownVotes,
        TS.TagUsageCount,
        TS.AvgTagScore,
        UA.QuestionCount,
        UA.AnswerCount AS UserAnswerCount,
        UA.TotalQuestionScore,
        UA.TotalAnswerScore,
        CS.CommentCount AS SubqueryCommentCount
    FROM 
        TopPosts TP
    JOIN 
        TagStats TS ON TP.Tags LIKE '%' || TS.TagName || '%'
    JOIN 
        UserActivity UA ON TP.OwnerUserId = UA.Id
    JOIN 
        CorrelatedSubquery CS ON TP.Id = CS.Id
)
SELECT 
    *
FROM 
    FinalResult
ORDER BY 
    PostRank, Score DESC;