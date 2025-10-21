-- {"query": "34063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 986} 
WITH RankedAnswers AS (
    SELECT 
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        U.Id AS AnswerOwnerId,
        U.Reputation AS AnswerOwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerRank
    FROM Posts A
    JOIN Users U ON A.OwnerUserId = U.Id
    WHERE A.PostTypeId = 2 -- Answers
),
TopAnswers AS (
    SELECT *
    FROM RankedAnswers
    WHERE AnswerRank <= 3
),
QuestionStats AS (
    SELECT 
        Q.Id AS QuestionId,
        Q.Title,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.Tags,
        QU.Id AS QuestionOwnerId,
        QU.DisplayName AS QuestionOwnerName,
        QU.Reputation AS QuestionOwnerReputation,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownVotes,
        MAX(B.Score) AS MaxBadgeScore
    FROM Posts Q
    LEFT JOIN Users QU ON Q.OwnerUserId = QU.Id
    LEFT JOIN Comments C ON C.PostId = Q.Id
    LEFT JOIN Votes V ON V.PostId = Q.Id
    LEFT JOIN (
        SELECT UserId, MAX(CASE WHEN Class=1 THEN 100 WHEN Class=2 THEN 10 WHEN Class=3 THEN 1 ELSE 0 END) AS Score
        FROM Badges
        GROUP BY UserId
    ) B ON B.UserId = Q.OwnerUserId
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.Title, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.Tags, QU.Id, QU.DisplayName, QU.Reputation
),
AnswerDetails AS (
    SELECT 
        TA.AnswerId,
        TA.QuestionId,
        TA.AnswerScore,
        TA.AnswerCreationDate,
        TA.AnswerOwnerId,
        U.DisplayName AS AnswerOwnerName,
        U.Reputation AS AnswerOwnerReputation,
        COUNT(DISTINCT C.Id) AS AnswerCommentCount,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS AnswerUpVotes,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS AnswerDownVotes,
        MAX(B.Score) AS AnswerMaxBadgeScore
    FROM TopAnswers TA
    LEFT JOIN Users U ON TA.AnswerOwnerId = U.Id
    LEFT JOIN Comments C ON C.PostId = TA.AnswerId
    LEFT JOIN Votes V ON V.PostId = TA.AnswerId
    LEFT JOIN (
        SELECT UserId, MAX(CASE WHEN Class=1 THEN 100 WHEN Class=2 THEN 10 WHEN Class=3 THEN 1 ELSE 0 END) AS Score
        FROM Badges
        GROUP BY UserId
    ) B ON B.UserId = TA.AnswerOwnerId
    GROUP BY TA.AnswerId, TA.QuestionId, TA.AnswerScore, TA.AnswerCreationDate, TA.AnswerOwnerId, U.DisplayName, U.Reputation
)
SELECT
    QS.QuestionId,
    QS.Title,
    QS.QuestionCreationDate,
    QS.QuestionScore,
    QS.ViewCount,
    QS.AnswerCount,
    QS.FavoriteCount,
    QS.Tags,
    QS.QuestionOwnerId,
    QS.QuestionOwnerName,
    QS.QuestionOwnerReputation,
    QS.CommentCount,
    QS.UpVotes AS QuestionUpVotes,
    QS.DownVotes AS QuestionDownVotes,
    QS.MaxBadgeScore AS QuestionOwnerMaxBadgeScore,
    AD.AnswerId,
    AD.AnswerScore,
    AD.AnswerCreationDate,
    AD.AnswerOwnerId,
    AD.AnswerOwnerName,
    AD.AnswerOwnerReputation,
    AD.AnswerCommentCount,
    AD.AnswerUpVotes,
    AD.AnswerDownVotes,
    AD.AnswerMaxBadgeScore
FROM QuestionStats QS
LEFT JOIN AnswerDetails AD ON QS.QuestionId = AD.QuestionId
WHERE QS.QuestionScore > 10
AND QS.AnswerCount >= 3
AND AD.AnswerScore > 5
ORDER BY QS.QuestionScore DESC, QS.FavoriteCount DESC, AD.AnswerScore DESC
LIMIT 50;