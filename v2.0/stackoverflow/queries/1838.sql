-- {"query": "1838.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1741}
WITH UserRelevantPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScoreAllPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsPosted,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersPosted,
        COUNT(DISTINCT p.AcceptedAnswerId) AS TotalAcceptedAnswersReceived,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountOnPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE (p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years') OR p.Id IS NULL)
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.UpVotes, u.DownVotes
    HAVING u.CreationDate <= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
SQLPerformanceAnswers AS (
    SELECT
        a.OwnerUserId AS UserId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        q.Id AS QuestionId
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
      AND q.PostTypeId = 1
      AND a.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
      AND q.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
      AND (
            (q.Tags LIKE '%<sql>%' AND q.Tags LIKE '%<performance>%')
            OR
            (q.Tags LIKE '%<database>%' AND q.Tags LIKE '%<optimization>%')
          )
),
UserSQLPerformanceAnswerAggregates AS (
    SELECT
        UserId,
        COUNT(AnswerId) AS NumRelevantAnswers,
        SUM(AnswerScore) AS CumulativeRelevantAnswerScore,
        AVG(AnswerScore) AS AverageRelevantAnswerScore
    FROM SQLPerformanceAnswers
    GROUP BY UserId
    HAVING COUNT(AnswerId) >= 5
),
UserUniqueQuestionTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT LOWER(TRIM(tag.value))) AS UniqueQuestionTagCount
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag(value)
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
    GROUP BY p.OwnerUserId
),
UserLatestBodyEdit AS (
    SELECT
        ph.UserId,
        ph.Comment AS LatestEditComment,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5
      AND ph.Comment IS NOT NULL
      AND LENGTH(TRIM(ph.Comment)) > 5
)
SELECT
    urs.DisplayName,
    urs.Reputation,
    urs.UserCreationDate,
    urs.TotalQuestionsPosted,
    urs.TotalAnswersPosted,
    urs.TotalQuestionViews,
    COALESCE(uspa.CumulativeRelevantAnswerScore, 0) AS CumulativeRelevantAnswerScore,
    COALESCE(uspa.AverageRelevantAnswerScore, 0.0) AS AverageRelevantAnswerScore,
    COALESCE(uut.UniqueQuestionTagCount, 0) AS TotalUniqueQuestionTags,
    COALESCE(
        (CAST(urs.UpVotes AS numeric) - urs.DownVotes) / NULLIF(CAST(urs.UpVotes AS numeric) + urs.DownVotes, 0),
        0.0
    ) AS NetVoteRatio,
    COALESCE(
        ule.LatestEditComment,
        'No recent relevant body edit comment found.'
    ) AS MostRecentBodyEditComment,
    (
        urs.Reputation * 0.05
        + urs.TotalQuestionViews * 0.001
        + urs.TotalAnswerScoreAllPosts * 0.01
        + urs.TotalAcceptedAnswersReceived * 10
        + urs.TotalFavoriteCountOnPosts * 0.5
        + COALESCE(uspa.NumRelevantAnswers, 0) * 2
        + COALESCE(uspa.CumulativeRelevantAnswerScore, 0) * 0.02
        + COALESCE(uut.UniqueQuestionTagCount, 0) * 0.1
        + CASE WHEN ule.LatestEditComment IS NOT NULL THEN 1 ELSE 0 END * 2
    ) AS EngagementScore,
    RANK() OVER (ORDER BY (
        urs.Reputation * 0.05
        + urs.TotalQuestionViews * 0.001
        + urs.TotalAnswerScoreAllPosts * 0.01
        + urs.TotalAcceptedAnswersReceived * 10
        + urs.TotalFavoriteCountOnPosts * 0.5
        + COALESCE(uspa.NumRelevantAnswers, 0) * 2
        + COALESCE(uspa.CumulativeRelevantAnswerScore, 0) * 0.02
        + COALESCE(uut.UniqueQuestionTagCount, 0) * 0.1
        + CASE WHEN ule.LatestEditComment IS NOT NULL THEN 1 ELSE 0 END * 2
    ) DESC, COALESCE(uspa.CumulativeRelevantAnswerScore, 0) DESC, urs.Reputation DESC) AS OverallRanking
FROM UserRelevantPostStats urs
INNER JOIN UserSQLPerformanceAnswerAggregates uspa ON urs.UserId = uspa.UserId
LEFT JOIN UserUniqueQuestionTags uut ON urs.UserId = uut.UserId
LEFT JOIN UserLatestBodyEdit ule ON urs.UserId = ule.UserId AND ule.rn = 1
WHERE urs.TotalAnswersPosted >= 10
  AND urs.Reputation > 50
ORDER BY EngagementScore DESC, OverallRanking ASC
LIMIT 10;