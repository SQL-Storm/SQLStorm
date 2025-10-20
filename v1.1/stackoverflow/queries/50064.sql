-- {"query": "50064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 800} 
WITH UserAnswerStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(P.Id) OVER (PARTITION BY U.Id) AS TotalAnswers,
        AVG(P.Score) OVER (PARTITION BY U.Id) AS AvgUserScore,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY U.Id) AS GoldBadges,
        P.Id AS AnswerId,
        P.ParentId AS QuestionId,
        P.Score AS AnswerScore,
        P.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY P.Score DESC, P.CreationDate DESC) AS rn
    FROM
        Users U
    JOIN
        Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 2
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    WHERE
        U.Reputation > 75000 AND U.Views > 1000
),
QuestionDetails AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        Q.Tags,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.FavoriteCount,
        Q.AnswerCount,
        A.Id AS AcceptedAnswerId,
        A.Score AS AcceptedAnswerScore
    FROM
        Posts Q
    LEFT JOIN
        Posts A ON Q.AcceptedAnswerId = A.Id
    WHERE
        Q.PostTypeId = 1 AND Q.ClosedDate IS NULL
),
AnswerActivity AS (
    SELECT
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
        MAX(CreationDate) AS LastVoteDate
    FROM
        Votes
    WHERE
        VoteTypeId IN (2, 3)
    GROUP BY
        PostId
)
SELECT
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalAnswers,
    UAS.GoldBadges,
    QD.Title AS QuestionTitle,
    QD.Tags,
    QD.QuestionScore,
    QD.ViewCount,
    UAS.AnswerScore,
    UAS.AnswerCreationDate,
    (SELECT COUNT(*) FROM Comments C WHERE C.PostId = UAS.AnswerId) AS CommentCount,
    AA.UpVotes,
    AA.DownVotes,
    (UAS.AnswerScore - QD.AcceptedAnswerScore) AS ScoreDeltaFromAccepted,
    (EXTRACT(EPOCH FROM (SELECT MIN(CreationDate) FROM Posts WHERE ParentId = UAS.QuestionId AND PostTypeId = 2)) - EXTRACT(EPOCH FROM UAS.AnswerCreationDate)) / 3600 AS HoursToAnswerAfterFirst
FROM
    UserAnswerStats UAS
JOIN
    QuestionDetails QD ON UAS.QuestionId = QD.QuestionId
JOIN
    AnswerActivity AA ON UAS.AnswerId = AA.PostId
WHERE
    UAS.rn <= 3 AND UAS.GoldBadges > 0 AND UAS.AnswerScore > UAS.AvgUserScore
    AND UAS.AnswerId != QD.AcceptedAnswerId AND QD.AcceptedAnswerScore IS NOT NULL
ORDER BY
    UAS.Reputation DESC,
    UAS.rn ASC,
    ScoreDeltaFromAccepted DESC
LIMIT 200;