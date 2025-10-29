-- {"query": "7635.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1459}
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScore,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
    MAX(p.CreationDate) AS LatestPostDate,
    MIN(p.CreationDate) AS FirstPostDate,
    -- DATEDIFF is not standard; use EXTRACT(EPOCH FROM ...) / 86400 for days in many dialects, or DATE_PART for Postgres.
    CAST((CAST('2024-10-01 12:34:56' AS TIMESTAMP) - MIN(p.CreationDate)) AS INTERVAL) AS DaysActiveInterval,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    -- normalize tags by removing surrounding <> if present
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2) END, ',') AS AllTags,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) AS TotalViewCount,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END), 0) AS AvgQuestionViews,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END), 0) AS ClosedQuestions,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END), 0) AS QuestionsWithAnswers,
    COALESCE(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END), 0) AS FavoriteQuestions,
    -- Window functions: any expressions used inside window ordering must be grouped or be windowed; use window functions that reference grouped aggregates by repeating aggregates as window inputs
    RANK() OVER (ORDER BY SUM(p.Score) DESC) AS ScoreRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS ActivityRank,
    ROW_NUMBER() OVER (ORDER BY u.CreationDate) AS UserRowNum,
    -- Correlated subquery for avg reputation in last 30 days: use standard interval syntax
    (
      SELECT AVG(r.Reputation)
      FROM Users r
      WHERE r.CreationDate <= u.CreationDate
        AND r.CreationDate >= (u.CreationDate - INTERVAL '30' DAY)
    ) AS AvgReputationLast30Days,
    -- Last post history type: standard SQL uses LIMIT 1 (or FETCH) and COALESCE
    COALESCE((
      SELECT ph.PostHistoryTypeId
      FROM PostHistory ph
      WHERE ph.UserId = u.Id
      ORDER BY ph.CreationDate DESC
      FETCH FIRST 1 ROW ONLY
    ), 0) AS LastPostActivityType,
    CASE
        WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1)
         AND EXISTS (SELECT 1 FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2)
        THEN 'QuestionAnswerer'
        WHEN EXISTS (SELECT 1 FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1)
        THEN 'Questioner'
        WHEN EXISTS (SELECT 1 FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.PostTypeId = 2)
        THEN 'Answerer'
        ELSE 'Inactive'
    END AS UserCategory,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> ''
        THEN CONCAT('Website: ', SUBSTRING(u.WebsiteUrl FROM 1 FOR 20))
        WHEN u.Location IS NOT NULL AND u.Location <> ''
        THEN CONCAT('Location: ', u.Location)
        ELSE 'No Profile Info'
    END AS ProfileSummary,
    ROUND(SUM(p.Score) * 1.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 2) AS AvgScorePerPost,
    ROUND(COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 2) AS QuestionPercentage,
    ROUND(COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0), 2) AS AnswerPercentage
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
    u.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    AND u.Reputation > 0
    AND (p.Id IS NULL OR p.PostTypeId IN (1, 2))
    AND (u.Id <> 0 OR u.Id IS NOT NULL)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.WebsiteUrl,
    u.Location
HAVING
    COUNT(DISTINCT p.Id) > 0
    AND COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
    AND (SUM(p.Score) > 0 OR COUNT(DISTINCT v.Id) > 0 OR COUNT(DISTINCT b.Id) > 0)
ORDER BY
    TotalScore DESC,
    Reputation DESC,
    LatestPostDate DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;