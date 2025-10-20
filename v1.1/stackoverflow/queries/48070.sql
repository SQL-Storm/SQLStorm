-- {"query": "48070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 818} 
WITH QuestionAnswers AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId AS QuestionOwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        COUNT(c.Id) AS CommentCountOnQuestionAndAnswers,
        AVG(c.Score) AS AvgCommentScoreOnQuestionAndAnswers
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON p.Id = c.PostId OR a.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT qa.QuestionId) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN qa.AcceptedAnswerCount > 0 THEN qa.QuestionId ELSE NULL END) AS QuestionsWithAcceptedAnswers,
        SUM(qa.AnswerCount) AS TotalAnswersGiven,
        AVG(qa.AvgAnswerScore) AS AvgScoreOfAnswersGiven,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN QuestionAnswers qa ON u.Id = qa.QuestionOwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate
)
SELECT
    qa.QuestionId,
    qa.QuestionTitle,
    qa.QuestionCreationDate,
    qa.QuestionScore,
    qa.AnswerCount,
    qa.AcceptedAnswerCount,
    qa.AvgAnswerScore,
    qa.MaxAnswerScore,
    qa.MinAnswerScore,
    qa.CommentCountOnQuestionAndAnswers,
    qa.AvgCommentScoreOnQuestionAndAnswers,
    ua.UserId AS QuestionOwnerUserId,
    ua.DisplayName AS QuestionOwnerDisplayName,
    ua.Reputation AS QuestionOwnerReputation,
    ua.UserCreationDate AS QuestionOwnerCreationDate,
    ua.QuestionsAsked AS QuestionOwnerQuestionsAsked,
    ua.QuestionsWithAcceptedAnswers AS QuestionOwnerQuestionsWithAcceptedAnswers,
    ua.TotalAnswersGiven AS QuestionOwnerTotalAnswersGiven,
    ua.AvgScoreOfAnswersGiven AS QuestionOwnerAvgScoreOfAnswersGiven,
    ua.TotalBadgesEarned AS QuestionOwnerTotalBadgesEarned,
    ua.LastBadgeDate AS QuestionOwnerLastBadgeDate,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = qa.QuestionId AND ph.PostHistoryTypeId IN (4, 6)) AS EditHistoryCount
FROM QuestionAnswers qa
JOIN UserActivity ua ON qa.QuestionOwnerUserId = ua.UserId
WHERE qa.QuestionScore > 100 AND qa.AnswerCount > 5
ORDER BY
    qa.QuestionScore DESC,
    qa.AnswerCount DESC
LIMIT 1000;