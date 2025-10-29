-- {"query": "4849.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1204} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        COUNT(c.Id) OVER(PARTITION BY p.Id) as CommentCountForPost
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserPostStats AS (
    SELECT
        rp.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COUNT(CASE WHEN rp.PostTypeName = 'Question' THEN rp.PostId ELSE NULL END) AS QuestionCount,
        AVG(CASE WHEN rp.PostTypeName = 'Question' THEN rp.PostScore ELSE NULL END) AS AvgQuestionScore,
        SUM(CASE WHEN rp.PostTypeName = 'Answer' THEN rp.PostScore ELSE 0 END) AS TotalAnswerScore,
        MAX(CASE WHEN rp.PostTypeName = 'Question' THEN rp.PostCreationDate ELSE NULL END) AS LatestQuestionDate,
        COUNT(CASE WHEN rp.CommentCountForPost > 0 THEN rp.PostId ELSE NULL END) AS PostsWithComments,
        SUM(CASE WHEN rp.rn <= 5 THEN 1 ELSE 0 END) AS Top5PostsCount
    FROM RankedPosts rp
    JOIN Users u ON rp.OwnerUserId = u.Id
    GROUP BY rp.OwnerUserId, u.DisplayName
),
AnswerQuality AS (
    SELECT
        a.ParentId AS QuestionId,
        AVG(a.Score) AS AvgAnswerScore,
        COUNT(a.Id) AS AnswerCountForQuestion
    FROM Posts a
    WHERE a.PostTypeId = 2 AND a.ParentId IS NOT NULL
    GROUP BY a.ParentId
),
QuestionDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.FavoriteCount,
        q.AnswerCount AS TotalAnswers,
        q.ClosedDate,
        COALESCE(aq.AvgAnswerScore, 0) AS AverageAnswerScore,
        aq.AnswerCountForQuestion AS ActualAnswerCount,
        CASE
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        CASE
            WHEN q.ClosedDate IS NOT NULL THEN DATEDIFF(day, q.ClosedDate, q.LastActivityDate)
            ELSE NULL
        END AS DaysSinceClosed,
        SUBSTRING(q.Tags, 2, LEN(q.Tags) - 2) AS CleanTags
    FROM Posts q
    LEFT JOIN AnswerQuality aq ON q.Id = aq.QuestionId
    WHERE q.PostTypeId = 1
)
SELECT
    ups.OwnerDisplayName,
    ups.QuestionCount,
    ups.AvgQuestionScore,
    ups.TotalAnswerScore,
    ups.Top5PostsCount,
    qd.QuestionTitle,
    qd.QuestionScore,
    qd.AverageAnswerScore,
    qd.ActualAnswerCount,
    qd.HasAcceptedAnswer,
    qd.DaysSinceClosed,
    CASE
        WHEN qd.CleanTags LIKE '%<sql>%' OR qd.CleanTags LIKE '%<database>%' OR qd.CleanTags LIKE '%<performance>%' THEN 'SQL/DB Related'
        WHEN qd.CleanTags LIKE '%<javascript>%' OR qd.CleanTags LIKE '%<python>%' OR qd.CleanTags LIKE '%<java>%' THEN 'Programming Language Related'
        ELSE 'Other'
    END AS TagCategory,
    CASE
        WHEN qd.QuestionScore > 100 AND qd.AverageAnswerScore > 50 AND qd.HasAcceptedAnswer = 1 THEN 'High Value'
        WHEN qd.QuestionScore < 0 AND qd.ActualAnswerCount > 5 THEN 'Controversial'
        WHEN qd.DaysSinceClosed IS NOT NULL AND qd.DaysSinceClosed > 365 THEN 'Long Closed'
        ELSE 'Standard'
    END AS QuestionStatus,
    CASE WHEN qd.QuestionOwnerUserId = ups.OwnerUserId THEN 'Owner' ELSE 'Delegate' END AS OwnershipCheck,
    COALESCE(pht.CommentCount, 0) AS PostHistoryEdits
FROM UserPostStats ups
JOIN QuestionDetails qd ON ups.OwnerUserId = qd.QuestionOwnerUserId
LEFT JOIN (
    SELECT
        PostId,
        COUNT(Id) AS CommentCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
) pht ON qd.QuestionId = pht.PostId
WHERE ups.QuestionCount > 10
ORDER BY ups.TotalAnswerScore DESC, ups.AvgQuestionScore DESC, qd.QuestionScore DESC
LIMIT 100;
