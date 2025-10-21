-- {"query": "32089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 526} 

WITH TopUsers AS (
    SELECT TOP 5 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS PostCount,
        SUM(Posts.Score) AS TotalScore
    FROM Users
    JOIN Posts ON Users.Id = Posts.OwnerUserId
    WHERE Posts.PostTypeId IN (1, 2) -- Select only Questions and Answers
    GROUP BY Users.Id, Users.DisplayName
    ORDER BY TotalScore DESC, PostCount DESC
),
UserPostDetails AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        U.DisplayName
    FROM Posts P
    JOIN TopUsers U ON P.OwnerUserId = U.UserId
    WHERE P.PostTypeId = 1 -- Select only Questions
),
LinkedComments AS (
    SELECT 
        C.Id AS CommentId,
        C.PostId,
        C.Text AS CommentText,
        C.Score AS CommentScore,
        C.CreationDate AS CommentDate
    FROM Comments C
    JOIN UserPostDetails UPD ON C.PostId = UPD.PostId
),
AggregatedResults AS (
    SELECT 
        UPD.UserId,
        UPD.DisplayName,
        UPD.PostId,
        UPD.Title,
        UPD.CreationDate,
        UPD.Score,
        UPD.ViewCount,
        UPD.AnswerCount,
        UPD.CommentCount,
        UPD.FavoriteCount,
        COUNT(LC.CommentId) AS TotalComments,
        SUM(LC.CommentScore) AS TotalCommentScores
    FROM UserPostDetails UPD
    LEFT JOIN LinkedComments LC ON UPD.PostId = LC.PostId
    GROUP BY UPD.UserId, UPD.DisplayName, UPD.PostId, UPD.Title, UPD.CreationDate, UPD.Score, UPD.ViewCount, UPD.AnswerCount, UPD.CommentCount, UPD.FavoriteCount
)
SELECT 
    AR.UserId,
    AR.DisplayName,
    AR.PostId,
    AR.Title,
    AR.CreationDate,
    AR.Score,
    AR.ViewCount,
    AR.AnswerCount,
    AR.CommentCount,
    AR.FavoriteCount,
    AR.TotalComments,
    AR.TotalCommentScores
FROM AggregatedResults AR
ORDER BY AR.TotalCommentScores DESC, AR.Score DESC, AR.ViewCount DESC;
