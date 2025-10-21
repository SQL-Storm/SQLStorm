-- {"query": "22090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1103} 
WITH high_reputation_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.Location, u.WebsiteUrl,
           CASE WHEN u.AboutMe IS NOT NULL THEN LENGTH(u.AboutMe) ELSE 0 END AS about_me_length
    FROM Users u
    WHERE u.Reputation > 500
      AND u.LastAccessDate > '2009-01-01'::timestamp
),
question_posts AS (
    SELECT p.Id AS post_id, p.OwnerUserId, p.Title,
           STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS tag_array,
           p.Score, p.ViewCount, p.AnswerCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS top_question_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND p.Tags IS NOT NULL
),
answer_posts AS (
    SELECT p.Id AS post_id, p.ParentId, p.OwnerUserId, p.Score, p.Body,
           CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted' ELSE 'Not Accepted' END AS acceptance_status
    FROM Posts p
    WHERE p.PostTypeId = 2
),
post_votes AS (
    SELECT v.PostId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes
    FROM Votes v
    GROUP BY v.PostId
),
comment_counts AS (
    SELECT c.PostId, COUNT(*) AS comment_count, MAX(c.Score) AS max_comment_score
    FROM Comments c
    WHERE c.CreationDate > '2010-01-01'::timestamp
    GROUP BY c.PostId
),
badge_summary AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
           SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 10 ELSE 1 END) AS total_badge_points
    FROM Badges b
    GROUP BY b.UserId
),
top_questions_by_user AS (
    SELECT qp.OwnerUserId,
           STRING_AGG(tag, ', ') AS top_tags,
           SUM(qp.Score) AS total_question_score,
           AVG(qp.ViewCount) AS avg_views,
           COUNT(*) AS question_count
    FROM question_posts qp
    CROSS JOIN LATERAL UNNEST(qp.tag_array) AS tag
    WHERE qp.top_question_rank <= 3
    GROUP BY qp.OwnerUserId
)
SELECT hru.DisplayName,
       COALESCE(LOCATE('http', COALESCE(hru.WebsiteUrl, '')), 0) AS website_has_http,
       hru.Reputation + COALESCE(bs.total_badge_points, 0) AS adjusted_reputation,
       RANK() OVER (ORDER BY hru.Reputation + COALESCE(bs.total_badge_points, 0) DESC) AS user_rank,
       CASE 
         WHEN qbu.question_count > 5 THEN 'Prolific Poster'
         WHEN hru.about_me_length > 1000 THEN 'Detailed Bio'
         ELSE 'Regular User'
       END AS user_category,
       qbu.top_tags,
       qbu.total_question_score,
       qbu.avg_views,
       (SELECT SUM(ap.Score) 
        FROM answer_posts ap 
        WHERE ap.OwnerUserId = hru.Id 
          AND EXISTS (SELECT 1 FROM post_votes pv WHERE pv.PostId = ap.post_id AND pv.upvotes > pv.downvotes)
       ) AS accepted_answer_score_total,
       (SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.UserId = hru.Id 
          AND ph.PostHistoryTypeId IN (4,5,6)
       ) AS edit_count,
       cc.comment_count,
       bs.gold_badges,
       bs.silver_badges,
       bs.bronze_badges
FROM high_reputation_users hru
LEFT JOIN badge_summary bs ON bs.UserId = hru.Id
LEFT JOIN top_questions_by_user qbu ON qbu.OwnerUserId = hru.Id
LEFT JOIN (
    SELECT OwnerUserId, SUM(comment_count) AS comment_count
    FROM Posts p
    LEFT JOIN comment_counts cc ON cc.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY OwnerUserId
) AS user_comment_totals ON user_comment_totals.OwnerUserId = hru.Id
LEFT JOIN comment_counts cc ON cc.PostId = (SELECT qp.post_id FROM question_posts qp WHERE qp.OwnerUserId = hru.Id LIMIT 1)
WHERE hru.Reputation > 1000
  AND (qbu.question_count IS NULL OR qbu.question_count > 1)
  AND EXISTS (
      SELECT 1 
      FROM answer_posts ap 
      WHERE ap.OwnerUserId = hru.Id 
        AND ap.acceptance_status = 'Accepted'
  )
ORDER BY adjusted_reputation DESC
LIMIT 100;