WITH
  recent_votes AS (
    SELECT
      v.PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)    AS up_votes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)    AS down_votes,
      SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END)    AS accepted,
      COUNT(*)                                            AS total_votes
    FROM Votes v
    WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
    GROUP BY v.PostId
  ),
  question_stats AS (
    SELECT
      p.Id                            AS question_id,
      p.Title                         AS title,
      p.ViewCount                     AS view_count,
      p.AnswerCount                   AS answer_count,
      p.Score                         AS question_score,
      COALESCE(rv.up_votes, 0)        AS up_votes,
      COALESCE(rv.down_votes, 0)      AS down_votes,
      COALESCE(rv.accepted, 0)        AS accepted_answers,
      COALESCE(rv.total_votes, 0)     AS total_votes,
      AVG(CASE WHEN a.PostTypeId = 2 THEN a.Score END)   AS avg_answer_score,
      ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.ViewCount DESC) AS view_rank,
      p.CreationDate                  AS creation_date,
      p.Id                            AS grp_id,
      p.CreationDate                  AS grp_creationdate,
      p.ViewCount                     AS grp_viewcount,
      p.AnswerCount                   AS grp_answercount,
      p.Score                         AS grp_score
    FROM Posts p
    LEFT JOIN recent_votes rv ON rv.PostId = p.Id
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
    GROUP BY
      p.Id,
      p.Title,
      p.ViewCount,
      p.AnswerCount,
      p.Score,
      rv.up_votes,
      rv.down_votes,
      rv.accepted,
      rv.total_votes,
      p.CreationDate
  )
SELECT
  qs.question_id,
  qs.title,
  qs.creation_date,
  qs.view_count,
  qs.answer_count,
  qs.question_score,
  qs.up_votes,
  qs.down_votes,
  qs.accepted_answers,
  qs.total_votes,
  qs.avg_answer_score,
  qs.view_rank,
  u.Id            AS asked_by_user_id,
  u.DisplayName   AS asked_by_user_name,
  u.Reputation    AS asker_reputation,
  u.Views         AS asker_total_views,
  u.UpVotes       AS asker_total_upvotes
FROM question_stats qs
JOIN Posts p ON p.Id = qs.question_id
JOIN Users u ON u.Id = p.OwnerUserId
ORDER BY qs.view_rank, qs.view_count DESC
LIMIT 200;