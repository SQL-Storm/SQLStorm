-- {"query": "4280.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1140}
WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore,
        RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.AnswerCount DESC) AS MonthlyAnswerRank,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.Score DESC) AS NextQuestionScore,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.Score DESC) AS PreviousQuestionScore
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
AnswerDetails AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2 AND a.ParentId IS NOT NULL
    GROUP BY a.ParentId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.ViewCount, 0) ELSE 0 END) AS TotalQuestionViews,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
TagQuestionCounts AS (
    SELECT
        TRIM(tag) AS TagName,
        COUNT(*) AS QuestionCount
    FROM Posts
    CROSS JOIN LATERAL (
        SELECT value AS tag
        FROM (
            SELECT regexp_split_to_table(
                regexp_replace(regexp_replace(coalesce(Tags, ''), '<', '', 'g'), '>', '', 'g'),
                E'\\s+'
            ) AS value
        ) s
    ) t
    WHERE PostTypeId = 1 AND ClosedDate IS NULL
    GROUP BY TRIM(tag)
),
HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 100000
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.QuestionScore,
    rq.QuestionViewCount,
    COALESCE(ad.AnswerCount, 0) AS ActualAnswerCount,
    COALESCE(ad.AvgAnswerScore, 0) AS AverageAnswerScore,
    rq.RankByScore,
    rq.MonthlyAnswerRank,
    (rq.QuestionScore - rq.PreviousQuestionScore) AS ScoreDifferenceFromPrevious,
    (rq.NextQuestionScore - rq.QuestionScore) AS ScoreDifferenceToNext,
    ua.QuestionCount AS UserTotalQuestions,
    ua.AnswerCount AS UserTotalAnswers,
    ua.TotalQuestionViews AS UserTotalQuestionViews,
    tqc.QuestionCount AS TagSpecificQuestionCount,
    CASE WHEN hr.Id IS NOT NULL THEN 'High Reputation Owner' ELSE 'Standard Reputation Owner' END AS OwnerStatus,
    UPPER(SUBSTRING(rq.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE
        WHEN rq.QuestionCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN 'Old'
        WHEN rq.QuestionCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month') THEN 'Mature'
        ELSE 'Recent'
    END AS QuestionAgeCategory,
    (rq.QuestionViewCount * 1.0 / NULLIF(rq.AnswerCount, 0)) AS ViewsPerAnswerRatio,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.QuestionId AND c.Score > 5) AS HighScoreCommentCount
FROM RankedQuestions rq
LEFT JOIN AnswerDetails ad ON rq.QuestionId = ad.QuestionId
LEFT JOIN UserActivity ua ON rq.OwnerDisplayName = ua.DisplayName
LEFT JOIN TagQuestionCounts tqc ON SUBSTRING(rq.Title FROM 1 FOR (COALESCE(NULLIF(position(' ' IN rq.Title),0), CHAR_LENGTH(rq.Title)+1)-1)) = tqc.TagName
LEFT JOIN HighReputationUsers hr ON rq.OwnerDisplayName = hr.DisplayName AND rq.OwnerReputation = hr.Reputation
WHERE rq.QuestionScore > 0
  AND rq.OwnerReputation > (SELECT AVG(Reputation) FROM Users)
  AND EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rq.QuestionId AND pl.LinkTypeId = 3)
ORDER BY rq.RankByScore
LIMIT 100;