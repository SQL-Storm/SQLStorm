WITH QuestionEdits AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id ELSE NULL END) AS TotalEdits
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalQuestionsAnswered,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        TotalQuestionsAnswered,
        TotalAnswersPosted,
        TotalQuestionsAsked,
        TotalBadges
    FROM UserActivity
    WHERE Reputation > 10000
),
RecentQuestions AS (
    SELECT
        Id AS QuestionId,
        Title,
        OwnerUserId,
        Score,
        AnswerCount,
        FavoriteCount,
        ViewCount,
        CreationDate AS QuestionCreationDate
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 day')
),
QuestionAnswerStats AS (
    SELECT
        rq.QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.Score AS QuestionScore,
        rq.AnswerCount,
        rq.FavoriteCount,
        rq.ViewCount,
        rq.QuestionCreationDate,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(DISTINCT a.Id) AS NumberOfAnswers,
        SUM(CASE WHEN p.Id = rq.QuestionId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent
    FROM RecentQuestions rq
    LEFT JOIN Posts a ON rq.QuestionId = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Posts p ON rq.QuestionId = p.AcceptedAnswerId AND p.PostTypeId = 1
    GROUP BY rq.QuestionId, rq.Title, rq.OwnerUserId, rq.Score, rq.AnswerCount, rq.FavoriteCount, rq.ViewCount, rq.QuestionCreationDate
),
ClosedQuestionsWithReasons AS (
    SELECT
        p.Id AS QuestionId,
        crt.Name AS CloseReason,
        COUNT(DISTINCT ph.Id) AS NumberOfCloseEvents
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS SMALLINT) = crt.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL
    GROUP BY p.Id, crt.Name
)
SELECT
    hru.DisplayName AS HighReputationUserName,
    hru.Reputation,
    hru.TotalQuestionsAsked,
    qas.Title AS QuestionTitle,
    qas.QuestionScore,
    qas.AvgAnswerScore,
    qas.NumberOfAnswers,
    qas.FavoriteCount,
    qas.ViewCount,
    qasr.CloseReason,
    qasr.NumberOfCloseEvents,
    COALESCE(qe.TotalEdits, 0) AS TotalEditsOnQuestion,
    CASE
        WHEN qe.LastBodyEditDate IS NOT NULL AND qe.LastTitleEditDate IS NOT NULL THEN
            CASE
                WHEN qe.LastBodyEditDate > qe.LastTitleEditDate THEN 'Body Edited Last'
                WHEN qe.LastTitleEditDate > qe.LastBodyEditDate THEN 'Title Edited Last'
                ELSE 'Title and Body Edited Simultaneously'
            END
        WHEN qe.LastBodyEditDate IS NOT NULL THEN 'Body Edited Last'
        WHEN qe.LastTitleEditDate IS NOT NULL THEN 'Title Edited Last'
        ELSE 'No Title or Body Edits'
    END AS LastEditType,
    CASE WHEN qas.IsAcceptedAnswerPresent > 0 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer
FROM HighReputationUsers hru
JOIN RecentQuestions rq ON hru.UserId = rq.OwnerUserId
JOIN QuestionAnswerStats qas ON rq.QuestionId = qas.QuestionId
LEFT JOIN ClosedQuestionsWithReasons qasr ON rq.QuestionId = qasr.QuestionId
LEFT JOIN QuestionEdits qe ON rq.QuestionId = qe.QuestionId
WHERE qas.QuestionScore > 50 OR qas.ViewCount > 1000
ORDER BY hru.Reputation DESC, qas.ViewCount DESC;