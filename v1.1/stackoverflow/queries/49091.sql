WITH PythonQuestions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.AcceptedAnswerId,
        p.CreationDate
    FROM Posts p
    WHERE
        p.PostTypeId = 1 -- Question
        AND p.Tags LIKE '%<python>%'
        AND p.OwnerUserId IS NOT NULL
),
PythonAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate
    FROM Posts p
    WHERE
        p.PostTypeId = 2 -- Answer
        AND p.OwnerUserId IS NOT NULL
),
UserPythonQuestionStats AS (
    SELECT
        pq.OwnerUserId AS UserId,
        COUNT(pq.PostId) AS TotalPythonQuestions,
        SUM(pq.Score) AS TotalPythonQuestionScore,
        AVG(pq.Score) AS AvgPythonQuestionScore,
        COUNT(CASE WHEN pq.AcceptedAnswerId IS NOT NULL THEN 1 END) AS PythonQuestionsWithAcceptedAnswer,
        MAX(pq.CreationDate) AS LastPythonQuestionDate
    FROM PythonQuestions pq
    GROUP BY pq.OwnerUserId
),
UserPythonAnswerStats AS (
    SELECT
        pa.OwnerUserId AS UserId,
        COUNT(pa.AnswerId) AS TotalPythonAnswers,
        SUM(pa.Score) AS TotalPythonAnswerScore,
        AVG(pa.Score) AS AvgPythonAnswerScore,
        COUNT(CASE WHEN pa.AnswerId = q.AcceptedAnswerId THEN 1 END) AS AcceptedPythonAnswersGiven,
        MAX(pa.CreationDate) AS LastPythonAnswerDate
    FROM PythonAnswers pa
    JOIN Posts q ON pa.QuestionId = q.Id
    WHERE q.PostTypeId = 1 -- Ensure it's a question
    GROUP BY pa.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM Badges b
    GROUP BY b.UserId
),
CombinedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(uqs.TotalPythonQuestions, 0) AS TotalPythonQuestions,
        COALESCE(uqs.TotalPythonQuestionScore, 0) AS TotalPythonQuestionScore,
        COALESCE(uqs.AvgPythonQuestionScore, 0) AS AvgPythonQuestionScore,
        COALESCE(uqs.PythonQuestionsWithAcceptedAnswer, 0) AS PythonQuestionsWithAcceptedAnswer,
        COALESCE(uqs.LastPythonQuestionDate, TIMESTAMP '1900-01-01 00:00:00') AS LastPythonQuestionDate,
        COALESCE(uas.TotalPythonAnswers, 0) AS TotalPythonAnswers,
        COALESCE(uas.TotalPythonAnswerScore, 0) AS TotalPythonAnswerScore,
        COALESCE(uas.AvgPythonAnswerScore, 0) AS AvgPythonAnswerScore,
        COALESCE(uas.AcceptedPythonAnswersGiven, 0) AS AcceptedPythonAnswersGiven,
        COALESCE(uas.LastPythonAnswerDate, TIMESTAMP '1900-01-01 00:00:00') AS LastPythonAnswerDate,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(ucs.AvgCommentScore, 0) AS AvgCommentScore,
        COALESCE(ucs.LastCommentDate, TIMESTAMP '1900-01-01 00:00:00') AS LastCommentDate,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.LastBadgeAwardDate, TIMESTAMP '1900-01-01 00:00:00') AS LastBadgeAwardDate,
        GREATEST(
            u.LastAccessDate,
            COALESCE(uqs.LastPythonQuestionDate, TIMESTAMP '1900-01-01 00:00:00'),
            COALESCE(uas.LastPythonAnswerDate, TIMESTAMP '1900-01-01 00:00:00'),
            COALESCE(ucs.LastCommentDate, TIMESTAMP '1900-01-01 00:00:00'),
            COALESCE(ubs.LastBadgeAwardDate, TIMESTAMP '1900-01-01 00:00:00')
        ) AS LatestActivityDate
    FROM Users u
    LEFT JOIN UserPythonQuestionStats uqs ON u.Id = uqs.UserId
    LEFT JOIN UserPythonAnswerStats uas ON u.Id = uas.UserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
    WHERE
        (uqs.UserId IS NOT NULL OR uas.UserId IS NOT NULL)
        AND u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR
)
SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.LatestActivityDate,
    c.TotalPythonQuestions,
    c.AvgPythonQuestionScore,
    c.PythonQuestionsWithAcceptedAnswer,
    c.TotalPythonAnswers,
    c.AvgPythonAnswerScore,
    c.AcceptedPythonAnswersGiven,
    c.TotalBadges,
    c.GoldBadges,
    c.SilverBadges,
    c.BronzeBadges,
    CASE
        WHEN c.TotalPythonAnswers > 0 THEN CAST(c.AcceptedPythonAnswersGiven AS DECIMAL) / c.TotalPythonAnswers
        ELSE 0
    END AS PythonAnswerAcceptanceRate,
    RANK() OVER (
        ORDER BY
            c.Reputation DESC,
            (CASE WHEN c.TotalPythonAnswers > 0 THEN CAST(c.AcceptedPythonAnswersGiven AS DECIMAL) / c.TotalPythonAnswers ELSE 0 END) DESC,
            c.AvgPythonQuestionScore DESC,
            c.PythonQuestionsWithAcceptedAnswer DESC,
            c.TotalPythonQuestions DESC,
            c.TotalPythonAnswers DESC,
            c.GoldBadges DESC,
            c.TotalBadges DESC,
            c.LatestActivityDate DESC
    ) AS PythonContributorRank
FROM CombinedUserActivity c
WHERE
    c.Reputation > 1000
    AND (c.TotalPythonQuestions > 0 OR c.TotalPythonAnswers > 0)
ORDER BY PythonContributorRank
LIMIT 50;