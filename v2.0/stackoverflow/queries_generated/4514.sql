-- {"query": "4514.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1139} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY DATE_TRUNC('month', u.CreationDate) ORDER BY u.Reputation DESC) AS MonthlyReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL AND u.Location IS NOT NULL AND u.WebsiteUrl IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT UserId, DisplayName, Reputation, UserCreationDate, PostCount, QuestionCount, AnswerCount
    FROM RankedUserActivity
    WHERE ReputationRank <= 100
),
RecentQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        Tags,
        CreationDate,
        Score,
        AnswerCount,
        ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS RecentQuestionNumber
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= DATE_TRUNC('year', CURRENT_DATE - INTERVAL '1 year')
),
QuestionTagStats AS (
    SELECT
        r.UserId,
        COUNT(DISTINCT q.Id) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN r.MonthlyReputationRank = 1 THEN q.Id ELSE NULL END) AS QuestionsByTopRankedUsersInMonth,
        AVG(q.Score) AS AverageQuestionScore,
        AVG(q.AnswerCount) AS AverageAnswerCount,
        SUM(LENGTH(q.Tags)) AS TotalTagLength,
        STRING_AGG(q.Title, ' | ') AS ConcatenatedTitles
    FROM RecentQuestions q
    JOIN RankedUserActivity r ON q.OwnerUserId = r.UserId
    WHERE q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<performance>%'
    GROUP BY r.UserId
),
UserActivitySummary AS (
    SELECT
        hru.UserId,
        hru.DisplayName,
        hru.Reputation,
        hru.UserCreationDate,
        hru.PostCount,
        hru.QuestionCount,
        hru.AnswerCount,
        COALESCE(qts.TotalQuestions, 0) AS SqlPerformanceQuestions,
        COALESCE(qts.QuestionsByTopRankedUsersInMonth, 0) AS QuestionsByTopRankedUsersInMonth,
        COALESCE(qts.AverageQuestionScore, 0.0) AS AvgQuestionScore,
        COALESCE(qts.AverageAnswerCount, 0.0) AS AvgAnswerCount,
        COALESCE(qts.TotalTagLength, 0) AS TotalTagLengthSum,
        COALESCE(qts.ConcatenatedTitles, 'No relevant titles found') AS UserTitles
    FROM HighReputationUsers hru
    LEFT JOIN QuestionTagStats qts ON hru.UserId = qts.UserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.PostCount,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.SqlPerformanceQuestions,
    uas.QuestionsByTopRankedUsersInMonth,
    uas.AvgQuestionScore,
    uas.AvgAnswerCount,
    uas.TotalTagLengthSum,
    uas.UserTitles,
    CASE
        WHEN uas.Reputation > 50000 THEN 'Guru'
        WHEN uas.Reputation BETWEEN 10000 AND 50000 THEN 'Expert'
        WHEN uas.Reputation BETWEEN 1000 AND 9999 THEN 'Experienced'
        ELSE 'Novice'
    END AS ReputationLevel,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = uas.UserId
          AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edits
          AND ph.CreationDate >= uas.UserCreationDate
    ) AS TotalEdits,
    (
        SELECT COUNT(*)
        FROM Comments c
        WHERE c.UserId = uas.UserId
          AND c.CreationDate >= uas.UserCreationDate
          AND c.Score > 5
    ) AS HighlyRatedComments
FROM UserActivitySummary uas
WHERE uas.PostCount > 10
ORDER BY uas.Reputation DESC, uas.PostCount DESC
LIMIT 50;
