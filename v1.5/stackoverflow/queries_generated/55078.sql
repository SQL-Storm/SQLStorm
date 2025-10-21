-- {"query": "55078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1827} 

WITH user_stats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
           COUNT(b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
           COUNT(b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_count,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_count,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS total_upvotes,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS total_downvotes
    FROM Users u
    LEFT JOIN Badges b          ON b.UserId = u.Id
    LEFT JOIN Posts p           ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v           ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
answer_stats AS (
    SELECT a.OwnerUserId AS user_id,
           AVG(a.Score)::numeric(10,2)                       AS avg_answer_score,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS median_answer_score
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
question_tag_agg AS (
    SELECT q.OwnerUserId AS user_id,
           jsonb_object_agg(t.TagName, tag_usage.cnt) AS tag_counts
    FROM Posts q
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><')) AS tag
    ) AS tg ON true
    JOIN Tags t               ON t.TagName = tg.tag
    JOIN (
        SELECT p.Id, COUNT(*) AS cnt
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.Id
    ) AS tag_usage          ON tag_usage.Id = q.Id
    GROUP BY q.OwnerUserId
),
close_reason_stats AS (
    SELECT ph.UserId,
           crt.Name                AS close_reason,
           COUNT(*)                AS close_votes
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id::text = ph.Comment
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId, crt.Name
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.gold_badges,
       us.silver_badges,
       us.bronze_badges,
       us.question_count,
       us.answer_count,
       us.total_upvotes,
       us.total_downvotes,
       COALESCE(as.avg_answer_score,0)    AS avg_answer_score,
       COALESCE(as.median_answer_score,0) AS median_answer_score,
       COALESCE(qta.tag_counts, '{}'::jsonb) AS tag_counts,
       jsonb_agg(
           jsonb_build_object('reason', crs.close_reason, 'votes', crs.close_votes)
       ) FILTER (WHERE crs.close_reason IS NOT NULL) AS close_reason_summary
FROM user_stats us
LEFT JOIN answer_stats as           ON as.user_id = us.Id
LEFT JOIN question_tag_agg qta       ON qta.user_id = us.Id
LEFT JOIN close_reason_stats crs    ON crs.UserId = us.Id
GROUP BY us.Id, us.DisplayName, us.Reputation,
         us.gold_badges, us.silver_badges, us.bronze_badges,
         us.question_count, us.answer_count,
         us.total_upvotes, us.total_downvotes,
         as.avg_answer_score, as.median_answer_score,
         qta.tag_counts
ORDER BY us.Reputation DESC
LIMIT 100;
