-- {"query": "55022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1562} 

WITH tag_stats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                                 AS total_questions,
        SUM(p.Score)                                AS total_score,
        AVG(p.ViewCount)                            AS avg_views,
        COUNT(DISTINCT p.OwnerUserId)               AS distinct_authors,
        JSONB_AGG(
            DISTINCT JSONB_BUILD_OBJECT(
                'question_id', p.Id,
                'title',       p.Title,
                'score',       p.Score,
                'creation',    p.CreationDate
            )
        ) FILTER (WHERE p.CreationDate >= NOW() - INTERVAL '30 days') 
        AS recent_questions_json
    FROM Tags t
    JOIN Posts p 
        ON p.PostTypeId = 1                                          -- only questions
       AND p.Tags LIKE ('%<' || t.TagName || '>%')                    -- tag appears in the list
    GROUP BY t.TagName
),

user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)   AS question_count,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)   AS answer_count,
        COALESCE(SUM(v.up_votes), 0)                  AS total_upvotes,
        COALESCE(SUM(v.down_votes), 0)                AS total_downvotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rank_by_rep
    FROM Users u
    LEFT JOIN Posts p 
        ON p.OwnerUserId = u.Id
    LEFT JOIN LATERAL (
        SELECT 
            COUNT(*) FILTER (WHERE vt.VoteTypeId = 2) AS up_votes,
            COUNT(*) FILTER (WHERE vt.VoteTypeId = 3) AS down_votes
        FROM Votes vt
        WHERE vt.PostId = p.Id
    ) v ON true
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

badge_agg AS (
    SELECT 
        b.UserId,
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'badge', b.Name,
                'date',  b.Date,
                'class', b.Class,
                'tagged', b.TagBased
            )
        ) AS badges_json
    FROM Badges b
    GROUP BY b.UserId
)

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    ua.question_count,
    ua.answer_count,
    ua.total_upvotes,
    ua.total_downvotes,
    ua.rank_by_rep,
    ba.badges_json,
    ts.TagName,
    ts.total_questions,
    ts.total_score,
    ts.avg_views,
    ts.distinct_authors,
    ts.recent_questions_json
FROM user_activity ua
JOIN Users u ON u.Id = ua.Id
LEFT JOIN badge_agg ba ON ba.UserId = u.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM tag_stats ts
    WHERE ts.TagName = ANY (
        SELECT UNNEST(
            STRING_TO_ARRAY(
                SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), 
                '><'
            )
        )
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
        LIMIT 5
    )
    ORDER BY ts.total_questions DESC
    LIMIT 1
) ts ON TRUE
WHERE ua.rank_by_rep <= 100
ORDER BY ua.rank_by_rep
LIMIT 100;
