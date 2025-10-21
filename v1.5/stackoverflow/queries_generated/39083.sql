-- {"query": "39083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3027} 

WITH
-- explode question tags
TaggedQuestions AS (
  SELECT
    p.id            AS question_id,
    p.owneruserid   AS user_id,
    p.title,
    p.creationdate,
    tg.tag
  FROM posts p
  CROSS JOIN LATERAL
    unnest(
      string_to_array(
        substring(p.tags, 2, length(p.tags) - 2),
        '><'
      )
    ) AS tg(tag)
  WHERE p.posttypeid = 1
    AND p.owneruserid IS NOT NULL
),
-- aggregate upvotes/downvotes received by each user
VotesByUser AS (
  SELECT
    p.owneruserid AS user_id,
    count(*)      AS vote_count
  FROM posts p
  JOIN votes v
    ON v.postid = p.id
   AND v.votetypeid IN (2, 3)
  GROUP BY p.owneruserid
),
-- count badges of each class per user
BadgeCounts AS (
  SELECT
    b.userid,
    sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_count,
    sum(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_count,
    sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_count
  FROM badges b
  GROUP BY b.userid
),
-- summarize each user’s overall activity
UserSummary AS (
  SELECT
    u.id                  AS user_id,
    u.displayname,
    u.reputation,
    count(DISTINCT tq.question_id)         AS questions_asked,
    count(DISTINCT CASE WHEN p.posttypeid = 2 THEN p.id END) AS answers_provided,
    coalesce(vb.vote_count, 0)             AS total_votes_received,
    coalesce(bc.gold_count,   0)           AS gold_badges,
    coalesce(bc.silver_count, 0)           AS silver_badges,
    coalesce(bc.bronze_count, 0)           AS bronze_badges
  FROM users u
  LEFT JOIN TaggedQuestions tq
    ON tq.user_id = u.id
  LEFT JOIN posts p
    ON p.owneruserid = u.id
  LEFT JOIN VotesByUser vb
    ON vb.user_id = u.id
  LEFT JOIN BadgeCounts bc
    ON bc.userid = u.id
  GROUP BY
    u.id, u.displayname, u.reputation,
    vb.vote_count,
    bc.gold_count, bc.silver_count, bc.bronze_count
),
-- rank users by votes and reputation
RankedUsers AS (
  SELECT
    us.*,
    row_number() OVER (ORDER BY us.total_votes_received DESC) AS vote_rank,
    row_number() OVER (ORDER BY us.reputation DESC)           AS rep_rank
  FROM UserSummary us
),
-- collect the distinct tags each user has asked questions in
RecentTags AS (
  SELECT
    tq.user_id,
    json_agg(DISTINCT tq.tag ORDER BY tq.tag) AS tag_list
  FROM TaggedQuestions tq
  GROUP BY tq.user_id
)
-- final selection: top 10 users by votes, with all metrics
SELECT
  ru.user_id,
  ru.displayname,
  ru.reputation,
  ru.questions_asked,
  ru.answers_provided,
  ru.total_votes_received,
  ru.gold_badges,
  ru.silver_badges,
  ru.bronze_badges,
  ru.vote_rank,
  ru.rep_rank,
  rt.tag_list
FROM RankedUsers ru
LEFT JOIN RecentTags rt
  ON rt.user_id = ru.user_id
WHERE ru.vote_rank <= 10
ORDER BY ru.vote_rank;
