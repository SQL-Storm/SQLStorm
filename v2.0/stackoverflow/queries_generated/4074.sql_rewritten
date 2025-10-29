-- {"query": "4074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1175} 
WITH RankedUserPosts AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.Score DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT r.PostId) AS TotalQuestions,
        SUM(CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END) AS QuestionsWithAnswers,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.Score) AS MaxQuestionScore,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN RankedUserPosts r ON u.Id = r.OwnerUserId
    WHERE u.Reputation > 1000 AND u.CreationDate < '2023-01-01'
    GROUP BY u.Id, u.DisplayName
),
FrequentTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TagCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) as TagRank
    FROM Tags t
    JOIN Posts p ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
    WHERE t.TagName NOT LIKE '%-%' -- Exclude tag names with hyphens, assuming they are meta-tags or similar
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 500
),
UserFavoriteTags AS (
    SELECT
        ups.UserId,
        ft.TagName,
        COUNT(p.Id) AS UserTagCount
    FROM UserPostStats ups
    JOIN Posts p ON ups.UserId = p.OwnerUserId AND p.PostTypeId = 1
    CROSS JOIN FrequentTags ft
    WHERE ft.TagRank <= 10 -- Consider top 10 most frequent tags
    AND p.Tags LIKE '%' || ft.TagName || '%'
    GROUP BY ups.UserId, ft.TagName
),
HighScoringAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 2 -- Answers
),
QuestionAnswerQuality AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.AnswerCount,
        q.Score AS QuestionScore,
        MAX(CASE WHEN hsa.rn = 1 THEN hsa.Score ELSE 0 END) AS BestAnswerScore,
        COUNT(CASE WHEN hsa.rn > 1 THEN hsa.AnswerId ELSE NULL END) AS NumberOfOtherAnswers,
        SUM(hsa.Score) AS TotalAnswerScore
    FROM Posts q
    JOIN HighScoringAnswers hsa ON q.Id = hsa.QuestionId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.AnswerCount, q.Score
)
SELECT
    ups.DisplayName AS UserDisplayName,
    ups.TotalQuestions,
    ups.QuestionsWithAnswers,
    ups.AvgQuestionScore,
    ups.MaxQuestionScore,
    ups.TotalFavorites,
    COALESCE(qaq.Title, 'N/A') AS TopQuestionTitle,
    qaq.QuestionScore AS TopQuestionScore,
    qaq.BestAnswerScore,
    qaq.NumberOfOtherAnswers,
    COALESCE(MAX(uft.UserTagCount), 0) AS MaxUserFavoriteTagCount,
    CASE
        WHEN ups.TotalQuestions > 100 THEN 'Prolific'
        WHEN ups.TotalQuestions > 20 THEN 'Active'
        ELSE 'Emerging'
    END AS UserActivityLevel,
    LENGTH(ups.DisplayName) AS DisplayNameLength,
    UPPER(SUBSTRING(ups.DisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
    (ups.AvgQuestionScore * ups.TotalFavorites) / NULLIF(ups.QuestionsWithAnswers, 0) AS EngagementRatio
FROM UserPostStats ups
LEFT JOIN QuestionAnswerQuality qaq ON ups.UserId = qaq.QuestionOwnerUserId
LEFT JOIN UserFavoriteTags uft ON ups.UserId = uft.UserId
GROUP BY
    ups.DisplayName,
    ups.TotalQuestions,
    ups.QuestionsWithAnswers,
    ups.AvgQuestionScore,
    ups.MaxQuestionScore,
    ups.TotalFavorites,
    qaq.Title,
    qaq.QuestionScore,
    qaq.BestAnswerScore,
    qaq.NumberOfOtherAnswers
ORDER BY
    ups.TotalQuestions DESC,
    ups.AvgQuestionScore DESC
LIMIT 100;