-- {"query": "55094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1519} 

WITH user_stats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                               AS question_count,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                               AS answer_count,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)                              AS question_score,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)                              AS answer_score,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)                               AS upvotes_given,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)                               AS downvotes_given,
        COUNT(b.Id)                                                               AS badge_total,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                                    AS gold_badges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                                    AS silver_badges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                                    AS bronze_badges
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes   v ON v.UserId = u.Id
    LEFT JOIN Badges  b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_usage AS (
    SELECT
        u.Id               AS UserId,
        t.TagName,
        COUNT(*)           AS tag_uses
    FROM Users u
    JOIN Posts p
        ON p.OwnerUserId = u.Id
        AND p.PostTypeId = 1                           -- only questions
    JOIN LATERAL (
        SELECT unnest(string_to_array(
                substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) pt ON TRUE
    JOIN Tags t
        ON t.TagName = pt.TagName
    GROUP BY u.Id, t.TagName
),
top_tags AS (
    SELECT
        UserId,
        jsonb_object_agg(TagName, tag_uses) AS tags_json
    FROM (
        SELECT
            tu.*,
            ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.tag_uses DESC) AS rn
        FROM tag_usage tu
    ) ranked
    WHERE rn <= 5
    GROUP BY UserId
)
SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.question_count,
    us.answer_count,
    us.question_score,
    us.answer_score,
    us.upvotes_given,
    us.downvotes_given,
    us.badge_total,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    COALESCE(tt.tags_json, '{}'::jsonb) AS top_tags,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.answer_score DESC) AS rank_by_rep_score
FROM user_stats us
LEFT JOIN top_tags tt
    ON tt.UserId = us.Id
WHERE us.Reputation > 10000
ORDER BY rank_by_rep_score
LIMIT 100;
