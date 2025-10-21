-- {"query": "35004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 968} 
WITH TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges
    FROM Users U
    LEFT JOIN Posts P ON P.OwnerUserId = U.Id
    LEFT JOIN Comments C ON C.UserId = U.Id
    LEFT JOIN Badges B ON B.UserId = U.Id
    WHERE U.Reputation > 10000
    GROUP BY U.Id, U.DisplayName, U.Reputation
    HAVING COUNT(DISTINCT P.Id) > 50
),
TopQuestions AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.Title,
        Q.Score,
        Q.ViewCount,
        Q.CreationDate,
        COUNT(DISTINCT A.Id) AS AnswerCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes
    FROM Posts Q
    LEFT JOIN Posts A ON A.ParentId = Q.Id AND A.PostTypeId = 2
    LEFT JOIN Votes V ON V.PostId = Q.Id
    WHERE Q.PostTypeId = 1
      AND Q.Score > 5
      AND Q.AnswerCount >= 2
      AND Q.ViewCount > 5000
    GROUP BY Q.Id, Q.OwnerUserId, Q.Title, Q.Score, Q.ViewCount, Q.CreationDate
),
TopAnswers AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId,
        A.Score,
        A.CreationDate,
        RANK() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerRank
    FROM Posts A
    WHERE A.PostTypeId = 2
      AND A.Score > 0
),
Commenters AS (
    SELECT 
        C.PostId,
        C.UserId,
        COUNT(*) AS CommentCount
    FROM Comments C
    WHERE C.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY C.PostId, C.UserId
),
BadgeCounts AS (
    SELECT
        B.UserId,
        B.Class,
        COUNT(*) AS BadgeCount
    FROM Badges B
    WHERE B.Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
    GROUP BY B.UserId, B.Class
)
SELECT 
    TU.Id AS UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.TotalPosts,
    TU.TotalComments,
    TU.TotalBadges,
    TQ.QuestionId,
    TQ.Title AS QuestionTitle,
    TQ.Score AS QuestionScore,
    TQ.ViewCount,
    TQ.CreationDate AS QuestionCreationDate,
    TQ.AnswerCount,
    TQ.Upvotes AS QuestionUpvotes,
    TA.AnswerId,
    TA.Score AS TopAnswerScore,
    TA.CreationDate AS AnswerCreationDate,
    BC_Gold.BadgeCount AS GoldBadges,
    BC_Silver.BadgeCount AS SilverBadges,
    BC_Bronze.BadgeCount AS BronzeBadges,
    COALESCE(SUM(CM.CommentCount),0) AS CommentsLastYear
FROM TopUsers TU
JOIN TopQuestions TQ ON TQ.OwnerUserId = TU.Id
JOIN TopAnswers TA ON TA.QuestionId = TQ.QuestionId AND TA.AnswerRank = 1
LEFT JOIN BadgeCounts BC_Gold   ON BC_Gold.UserId = TU.Id AND BC_Gold.Class = 1
LEFT JOIN BadgeCounts BC_Silver ON BC_Silver.UserId = TU.Id AND BC_Silver.Class = 2
LEFT JOIN BadgeCounts BC_Bronze ON BC_Bronze.UserId = TU.Id AND BC_Bronze.Class = 3
LEFT JOIN Commenters CM ON CM.PostId = TQ.QuestionId AND CM.UserId = TU.Id
GROUP BY TU.Id, TU.DisplayName, TU.Reputation, TU.TotalPosts, TU.TotalComments, TU.TotalBadges,
         TQ.QuestionId, TQ.Title, TQ.Score, TQ.ViewCount, TQ.CreationDate, TQ.AnswerCount, TQ.Upvotes,
         TA.AnswerId, TA.Score, TA.CreationDate,
         BC_Gold.BadgeCount, BC_Silver.BadgeCount, BC_Bronze.BadgeCount
ORDER BY TU.Reputation DESC, TQ.ViewCount DESC, TQ.QuestionId
LIMIT 100;