-- {"query": "35005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 757} 
WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.UserId = u.Id
    WHERE u.Reputation >= (
        SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY Reputation) FROM Users
    )
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ActiveQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        ARRAY(
            SELECT t.TagName
            FROM Tags t
            WHERE POSITION('>' || t.TagName || '<' IN p.Tags) > 0
        ) AS TagNames
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.AnswerCount > 2
        AND p.Score > 5
        AND p.ViewCount > 100
        AND p.CreationDate > (cast('2024-10-01' as date) - INTERVAL '365 days')
),
TopAnswerers AS (
    SELECT
        pa.OwnerUserId,
        COUNT(*) AS AnswerCount
    FROM Posts pa
    WHERE pa.PostTypeId = 2
        AND pa.CreationDate > (cast('2024-10-01' as date) - INTERVAL '365 days')
        AND pa.Score >= 2
    GROUP BY pa.OwnerUserId
    HAVING COUNT(*) > 10
),
BadgesLastYear AS (
    SELECT
        b.UserId,
        COUNT(*) AS RecentBadges
    FROM Badges b
    WHERE b.Date > (cast('2024-10-01' as date) - INTERVAL '365 days')
    GROUP BY b.UserId
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    tu.TotalAnswers,
    tu.TotalUpVotesGiven,
    tu.TotalDownVotesGiven,
    COALESCE(tal.AnswerCount, 0) AS RecentHighScoredAnswers,
    COALESCE(bly.RecentBadges, 0) AS BadgesLastYear,
    COUNT(DISTINCT aq.QuestionId) AS LinkedRecentActiveQuestions,
    ARRAY_AGG(DISTINCT tag) FILTER (WHERE tag IS NOT NULL) AS TagDiversity
FROM TopUsers tu
LEFT JOIN TopAnswerers tal ON tal.OwnerUserId = tu.UserId
LEFT JOIN BadgesLastYear bly ON bly.UserId = tu.UserId
LEFT JOIN ActiveQuestions aq ON aq.OwnerUserId = tu.UserId
LEFT JOIN LATERAL UNNEST(aq.TagNames) AS tag ON TRUE
GROUP BY
    tu.UserId, tu.DisplayName, tu.Reputation, tu.TotalPosts, tu.TotalAnswers, tu.TotalUpVotesGiven, tu.TotalDownVotesGiven, tal.AnswerCount, bly.RecentBadges
ORDER BY
    tu.Reputation DESC, RecentHighScoredAnswers DESC NULLS LAST, BadgesLastYear DESC NULLS LAST
LIMIT 25;