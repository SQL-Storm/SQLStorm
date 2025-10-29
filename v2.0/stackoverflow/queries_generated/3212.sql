-- {"query": "3212.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2054} 

WITH
    TopQuestions AS (
        SELECT
            p.Id,
            p.Title,
            p.CreationDate,
            p.Score,
            p.OwnerUserId,
            ROW_NUMBER() OVER (
                PARTITION BY p.OwnerUserId
                ORDER BY p.Score DESC, p.CreationDate DESC
            ) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1               -- questions
          AND p.Tags LIKE '%<sql>%'          -- contains the <sql> tag
          AND p.Score > 0
    ),

    UserAnswerStats AS (
        SELECT
            u.Id                                    AS UserId,
            u.DisplayName,
            COUNT(a.Id) FILTER (WHERE a.Score >= 5) AS HighScoreAnswers,
            COUNT(a.Id)                             AS TotalAnswers,
            SUM(COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) AS NetVoteScore,
            MAX(a.CreationDate)                     AS LastAnswerDate
        FROM Users u
        LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
        LEFT JOIN (
            SELECT
                p.Id,
                SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
                SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
            FROM Posts p
            JOIN Votes v   ON v.PostId = p.Id
            JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
            GROUP BY p.Id
        ) v ON v.Id = a.Id
        GROUP BY u.Id, u.DisplayName
        HAVING COUNT(a.Id) > 0
    ),

    BadgeSummary AS (
        SELECT
            b.UserId,
            STRING_AGG(
                CASE
                    WHEN b.Class = 1 THEN 'Gold'
                    WHEN b.Class = 2 THEN 'Silver'
                    ELSE 'Bronze'
                END, ', '
            )                      AS BadgeClasses,
            COUNT(*)               AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),

    ClosedQuestionInfo AS (
        SELECT
            ph.PostId,
            MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDate,
            MIN(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenedDate,
            MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS INT) END) AS CloseReasonId
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10, 11)
        GROUP BY ph.PostId
    ),

    Combined AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ua.HighScoreAnswers,
            ua.TotalAnswers,
            ua.NetVoteScore,
            ua.LastAnswerDate,
            COALESCE(bs.BadgeClasses, '') AS BadgeClasses,
            COALESCE(bs.TotalBadges, 0)    AS BadgeCount,
            tq.Title                       AS TopQuestionTitle,
            tq.Score                       AS TopQuestionScore,
            cq.ClosedDate,
            cq.ReopenedDate,
            cr.Name                        AS CloseReasonName,
            CASE
                WHEN cq.ClosedDate IS NOT NULL AND cq.ReopenedDate IS NULL THEN 'Closed'
                WHEN cq.ClosedDate IS NOT NULL AND cq.ReopenedDate IS NOT NULL THEN 'Reopened'
                ELSE 'Open'
            END                            AS QuestionStatus
        FROM Users u
        LEFT JOIN UserAnswerStats ua    ON ua.UserId = u.Id
        LEFT JOIN BadgeSummary bs       ON bs.UserId = u.Id
        LEFT JOIN TopQuestions tq       ON tq.OwnerUserId = u.Id AND tq.rn = 1
        LEFT JOIN ClosedQuestionInfo cq ON cq.PostId = tq.Id
        LEFT JOIN CloseReasonTypes cr   ON cr.Id = cq.CloseReasonId
        WHERE u.Reputation > 10000
          AND (ua.NetVoteScore IS NULL OR ua.NetVoteScore > 0)
    )

SELECT *
FROM Combined
WHERE QuestionStatus = 'Closed'

UNION ALL

SELECT
    Id,
    DisplayName,
    Reputation,
    HighScoreAnswers,
    TotalAnswers,
    NetVoteScore,
    LastAnswerDate,
    BadgeClasses,
    BadgeCount,
    NULL AS TopQuestionTitle,
    NULL AS TopQuestionScore,
    NULL AS ClosedDate,
    NULL AS ReopenedDate,
    NULL AS CloseReasonName,
    'NoClosedQuestion' AS QuestionStatus
FROM Combined
WHERE QuestionStatus <> 'Closed'

ORDER BY Reputation DESC, NetVoteScore DESC
LIMIT 100;
