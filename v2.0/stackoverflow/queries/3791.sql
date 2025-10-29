WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
AnswerMetrics AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*)                               AS AnswerCount,
        SUM(CASE WHEN p.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreAnswers,
        AVG(p.Score)                           AS AvgScore,
        MAX(p.CreationDate)                    AS LastAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
ClosedDuplicateQuestions AS (
    SELECT 
        q.Id                AS QuestionId,
        q.Title,
        q.OwnerUserId       AS QuestionOwner,
        q.CreationDate,
        ph.CreationDate     AS ClosedDate,
        CAST(ph.Comment AS INTEGER)   AS DuplicateOfId,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts q
    JOIN PostHistory ph ON ph.PostId = q.Id
    WHERE q.PostTypeId = 1
      AND ph.PostHistoryTypeId = 10
      AND ph.Comment ~ '^\d+$'
),
QuestionAnswerLink AS (
    SELECT 
        qa.QuestionId,
        qa.AnswerId,
        a.OwnerUserId        AS AnswerOwner,
        q.OwnerUserId        AS QuestionOwner,
        qa.Score,
        qa.CreationDate,
        COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0) AS NetVote
    FROM (
        SELECT 
            p.ParentId  AS QuestionId,
            p.Id        AS AnswerId,
            p.Score,
            p.CreationDate
        FROM Posts p
        WHERE p.PostTypeId = 2
    ) qa
    LEFT JOIN Posts a ON a.Id = qa.AnswerId
    LEFT JOIN Posts q ON q.Id = qa.QuestionId
    LEFT JOIN (
        SELECT 
            pv.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes pv
        JOIN VoteTypes vt ON vt.Id = pv.VoteTypeId
        GROUP BY pv.PostId
    ) v ON v.PostId = qa.AnswerId
),
Combined AS (
    SELECT 
        us.Id                           AS UserId,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        COALESCE(am.AnswerCount, 0)      AS TotalAnswers,
        COALESCE(am.HighScoreAnswers, 0) AS HighScoreAnswers,
        COALESCE(am.AvgScore, 0)         AS AvgAnswerScore,
        COALESCE(am.LastAnswerDate, TIMESTAMP '1970-01-01 00:00:00') AS LastAnswerDate,
        COUNT(DISTINCT cdq.QuestionId) FILTER (WHERE cdq.QuestionOwner = us.Id) 
                                          AS QuestionsClosedAsDuplicate,
        COUNT(DISTINCT qal.AnswerId)   FILTER (WHERE qal.AnswerOwner = us.Id) 
                                          AS AnswersToDuplicateQs,
        SUM(qal.NetVote)               FILTER (WHERE qal.AnswerOwner = us.Id) 
                                          AS NetVoteOnAnswersToDuplicateQs
    FROM UserStats us
    LEFT JOIN AnswerMetrics am      ON am.UserId = us.Id
    LEFT JOIN ClosedDuplicateQuestions cdq ON cdq.QuestionOwner = us.Id
    LEFT JOIN QuestionAnswerLink qal ON qal.QuestionId = cdq.QuestionId
    GROUP BY 
        us.Id, us.DisplayName, us.Reputation, us.NetVotes,
        us.GoldBadges, us.SilverBadges, us.BronzeBadges,
        am.AnswerCount, am.HighScoreAnswers, am.AvgScore, am.LastAnswerDate
),
Ranked AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY Reputation DESC, NetVotes DESC) AS RepRank,
        ROW_NUMBER() OVER (PARTITION BY DisplayName ORDER BY LastAnswerDate DESC) AS RecentAnswerSeq
    FROM Combined
    WHERE Reputation > 1000
      AND TotalAnswers >= 10
)
SELECT *
FROM Ranked
WHERE RepRank <= 100

UNION ALL

SELECT 
    NULL                        AS UserId,
    'Aggregated Summary'        AS DisplayName,
    NULL                        AS Reputation,
    NULL                        AS NetVotes,
    NULL                        AS GoldBadges,
    NULL                        AS SilverBadges,
    NULL                        AS BronzeBadges,
    SUM(TotalAnswers)           AS TotalAnswers,
    SUM(HighScoreAnswers)       AS HighScoreAnswers,
    AVG(AvgAnswerScore)         AS AvgAnswerScore,
    MAX(LastAnswerDate)         AS LastAnswerDate,
    SUM(QuestionsClosedAsDuplicate) AS QuestionsClosedAsDuplicate,
    SUM(AnswersToDuplicateQs)   AS AnswersToDuplicateQs,
    SUM(NetVoteOnAnswersToDuplicateQs) AS NetVoteOnAnswersToDuplicateQs,
    NULL                        AS RepRank,
    NULL                        AS RecentAnswerSeq
FROM Ranked
EXCEPT
SELECT *
FROM Ranked
WHERE RepRank <= 100

ORDER BY RepRank ASC NULLS LAST, TotalAnswers DESC;