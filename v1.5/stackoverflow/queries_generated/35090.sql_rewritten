-- {"query": "35090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 696} 
WITH PopularQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
      AND p.Score >= 10
      AND p.ViewCount >= 1000
),
PopularAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.Score > 0
      AND a.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted
    FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING u.Reputation > 10000
),
BadgesCount AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    pq.QuestionId,
    pq.Title,
    pq.CreationDate AS QuestionDate,
    pq.Score AS QuestionScore,
    pq.ViewCount,
    pq.AnswerCount,
    qu.DisplayName AS QuestionAuthor,
    qu.Reputation AS AuthorReputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    COUNT(DISTINCT pa.AnswerId) AS NumPopularAnswers,
    COALESCE(SUM(pa.AnswerScore), 0) AS TotalPopularAnswerScore,
    MAX(pa.AnswerScore) AS MaxSingleAnswerScore,
    ARRAY_AGG(DISTINCT au.DisplayName) FILTER (WHERE au.DisplayName IS NOT NULL) AS TopAnswerers
FROM PopularQuestions pq
    LEFT JOIN PopularAnswers pa ON pa.QuestionId = pq.QuestionId
    LEFT JOIN Users qu ON pq.OwnerUserId = qu.Id
    LEFT JOIN TopUsers au ON pa.AnswererId = au.UserId
    LEFT JOIN BadgesCount bc ON bc.UserId = pq.OwnerUserId
GROUP BY
    pq.QuestionId, pq.Title, pq.CreationDate, pq.Score, pq.ViewCount, pq.AnswerCount,
    qu.DisplayName, qu.Reputation,
    bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
ORDER BY
    pq.Score DESC, pq.ViewCount DESC
LIMIT 50;