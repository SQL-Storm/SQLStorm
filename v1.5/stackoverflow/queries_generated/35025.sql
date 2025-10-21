-- {"query": "35025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 533} 
WITH recent_questions AS (
    SELECT
        p.Id AS QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '90 days'
      AND p.OwnerUserId IS NOT NULL
),
top_users AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS NumQuestions,
        SUM(p.Score) AS TotalScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '90 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 5
),
popular_tags AS (
    SELECT
        unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS Tag,
        COUNT(*) AS Occurrences
    FROM recent_questions rq
    WHERE rq.rn = 1
    GROUP BY Tag
    HAVING COUNT(*) > 10
),
high_activity_posts AS (
    SELECT
        rq.QuestionId,
        rq.Title,
        rq.OwnerUserId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.QuestionId) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.QuestionId AND v.VoteTypeId IN (2,3)) AS VoteCount
    FROM recent_questions rq
    WHERE rq.rn = 1
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.NumQuestions,
    tu.TotalScore,
    pa.Tag,
    hap.QuestionId,
    hap.Title AS QuestionTitle,
    hap.CommentCount,
    hap.VoteCount
FROM top_users tu
JOIN recent_questions rq ON rq.OwnerUserId = tu.UserId AND rq.rn = 1
JOIN high_activity_posts hap ON hap.QuestionId = rq.QuestionId
JOIN popular_tags pa ON rq.Tags LIKE '%' || pa.Tag || '%'
ORDER BY tu.TotalScore DESC, hap.VoteCount DESC, hap.CommentCount DESC
LIMIT 50;