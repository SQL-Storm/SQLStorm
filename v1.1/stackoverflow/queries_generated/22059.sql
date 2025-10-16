-- {"query": "22059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 736} 
WITH GoldBadgeUsers AS (
    SELECT UserId, Name AS BadgeName
    FROM Badges
    WHERE Class = 1 AND Name LIKE '%gold%' OR Class = 1 AND TagBased = 1
),
QuestionStats AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CreationDate,
        CASE WHEN p.Tags IS NOT NULL THEN string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') ELSE NULL END AS TagArray,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3) AND v.UserId IS NOT NULL) AS VoteCount,
        (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)) AS NetVotes
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserQuestionAggregates AS (
    SELECT 
        q.OwnerUserId,
        COUNT(q.Id) AS TotalQuestions,
        AVG(CASE WHEN q.Score > 10 THEN q.Score ELSE NULL END) AS AvgHighScore,
        SUM(q.NetVotes) AS TotalNetVotes,
        MAX(q.ViewCount) AS MaxViews
    FROM QuestionStats q
    GROUP BY q.OwnerUserId
),
RankedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ua.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(ua.AvgHighScore, 0) AS AvgHighScore,
        COALESCE(ua.TotalNetVotes, 0) AS TotalNetVotes,
        COALESCE(ua.MaxViews, 0) AS MaxViews,
        g.BadgeName,
        ROW_NUMBER() OVER (ORDER BY (COALESCE(ua.TotalNetVotes, 0) + u.Reputation / 10.0) DESC) AS Rank
    FROM Users u
    LEFT OUTER JOIN GoldBadgeUsers g ON u.Id = g.UserId
    LEFT OUTER JOIN UserQuestionAggregates ua ON u.Id = ua.OwnerUserId
    WHERE g.BadgeName IS NOT NULL OR ua.TotalQuestions > 0
)
SELECT 
    ru.Rank,
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalQuestions,
    ROUND(ru.AvgHighScore, 2) AS AvgHighScore,
    ru.TotalNetVotes,
    ru.MaxViews,
    ru.BadgeName,
    CASE 
        WHEN ru.TotalQuestions > 100 AND ru.AvgHighScore > 20 THEN 'SuperUser'
        WHEN ru.TotalQuestions > 50 OR ru.Reputation > 50000 THEN 'Pro'
        ELSE 'Amateur'
    END AS UserLevel,
    (ru.TotalNetVotes - ru.TotalQuestions) AS NetVotePerQuestion,
    COALESCE(
        (SELECT STRING_AGG(UNNEST(ARRAY['tech', 'sql', 'performance']), ', ')
         FROM QuestionStats qs 
         WHERE qs.OwnerUserId = ru.Id AND qs.NetVotes > 0 LIMIT 1), 'None'
    ) AS SampleTags
FROM RankedUsers ru
WHERE ru.Rank <= 100
ORDER BY ru.Rank, ru.TotalNetVotes DESC;