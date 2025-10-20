-- {"query": "52069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 695} 
WITH top_tags AS (
    SELECT t.tag, COUNT(p.Id) AS post_count
    FROM Posts p
    CROSS JOIN unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
    WHERE p.PostTypeId = 1
    GROUP BY t.tag
    ORDER BY post_count DESC
    LIMIT 10
),
user_contributions AS (
    SELECT p.OwnerUserId AS UserId, t.tag, COUNT(p.Id) AS num_questions, SUM(p.Score) AS total_score
    FROM Posts p
    CROSS JOIN unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag)
    WHERE p.PostTypeId = 1 AND t.tag IN (SELECT tag FROM top_tags)
    GROUP BY p.OwnerUserId, t.tag
),
badge_counts AS (
    SELECT UserId, COUNT(*) AS badge_count
    FROM Badges
    GROUP BY UserId
),
vote_stats AS (
    SELECT v.UserId, COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes_received,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes_received
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
comment_stats AS (
    SELECT c.UserId, COUNT(c.Id) AS comment_count
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
user_agg AS (
    SELECT uc.UserId, u.DisplayName, u.Reputation, u.CreationDate,
           SUM(uc.num_questions) AS total_questions, SUM(uc.total_score) AS total_score,
           COALESCE(bc.badge_count, 0) AS badge_count,
           COALESCE(vs.upvotes_received, 0) AS upvotes_received,
           COALESCE(vs.downvotes_received, 0) AS downvotes_received,
           COALESCE(cs.comment_count, 0) AS comment_count
    FROM user_contributions uc
    JOIN Users u ON uc.UserId = u.Id
    LEFT JOIN badge_counts bc ON uc.UserId = bc.UserId
    LEFT JOIN vote_stats vs ON uc.UserId = vs.UserId
    LEFT JOIN comment_stats cs ON uc.UserId = cs.UserId
    GROUP BY uc.UserId, u.DisplayName, u.Reputation, u.CreationDate, bc.badge_count, vs.upvotes_received, vs.downvotes_received, cs.comment_count
),
ranked_users AS (
    SELECT *, RANK() OVER (ORDER BY total_questions DESC, total_score DESC, upvotes_received DESC) AS rank,
             ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY total_questions DESC) AS subrank
    FROM user_agg
)
SELECT ru.*, ph.total_edits, ph.last_edit_date
FROM ranked_users ru
LEFT JOIN (
    SELECT ph.UserId, COUNT(ph.Id) AS total_edits, MAX(ph.CreationDate) AS last_edit_date
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
) ph ON ru.UserId = ph.UserId
ORDER BY ru.rank, ru.total_score DESC
LIMIT 50;