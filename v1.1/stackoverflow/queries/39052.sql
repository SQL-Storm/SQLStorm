WITH
  questions AS (
    SELECT
      p.id            AS post_id,
      p.title,
      p.owneruserid,
      p.creationdate,
      p.viewcount,
      unnest(
        string_to_array(
          substring(p.tags, 2, length(p.tags) - 2),
          E'><'
        )
      ) AS tag
    FROM posts p
    WHERE p.posttypeid = 1
  ),
  comment_stats AS (
    SELECT
      postid,
      count(*)       AS comments,
      avg(score)     AS avg_comment_score
    FROM comments
    GROUP BY postid
  ),
  vote_stats AS (
    SELECT
      postid,
      sum(CASE WHEN votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
      sum(CASE WHEN votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
      sum(coalesce(bountyamount,0))               AS bounty_total
    FROM votes
    GROUP BY postid
  ),
  dup_stats AS (
    SELECT
      relatedpostid AS post_id,
      sum(CASE WHEN linktypeid = 3 THEN 1 ELSE 0 END) AS duplicates
    FROM postlinks
    GROUP BY relatedpostid
  ),
  tag_metrics AS (
    SELECT
      q.tag,
      count(*)                                   AS num_questions,
      avg(q.viewcount)                           AS avg_views,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY q.viewcount) AS med_views,
      avg(cs.comments)                           AS avg_comments,
      avg(vs.upvotes - vs.downvotes)             AS avg_net_votes,
      avg(ds.duplicates)                         AS avg_duplicates
    FROM questions q
    LEFT JOIN comment_stats cs ON cs.postid = q.post_id
    LEFT JOIN vote_stats vs    ON vs.postid = q.post_id
    LEFT JOIN dup_stats ds     ON ds.post_id = q.post_id
    GROUP BY q.tag
  ),
  user_metrics AS (
    SELECT
      u.id                   AS user_id,
      u.displayname,
      u.reputation,
      count(DISTINCT q.id)   AS questions,
      count(DISTINCT a.id)   AS answers,
      CASE WHEN count(a.id) = 0 THEN NULL ELSE avg(a.score) END AS avg_answer_score,
      sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold,
      sum(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver,
      sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze
    FROM users u
    LEFT JOIN posts q  ON q.owneruserid = u.id AND q.posttypeid = 1
    LEFT JOIN posts a  ON a.owneruserid = u.id AND a.posttypeid = 2
    LEFT JOIN badges b ON b.userid = u.id
    GROUP BY u.id, u.displayname, u.reputation
  ),
  tag_user AS (
    SELECT
      tm.tag,
      um.user_id,
      um.displayname,
      um.reputation,
      um.questions,
      um.answers,
      um.avg_answer_score,
      um.gold,
      um.silver,
      um.bronze
    FROM tag_metrics tm
    JOIN questions q   ON q.tag = tm.tag
    JOIN user_metrics um ON um.user_id = q.owneruserid
    GROUP BY
      tm.tag,
      um.user_id,
      um.displayname,
      um.reputation,
      um.questions,
      um.answers,
      um.avg_answer_score,
      um.gold,
      um.silver,
      um.bronze
  ),
  rank_by_tag AS (
    SELECT
      tag,
      displayname,
      reputation,
      questions,
      answers,
      avg_answer_score,
      gold,
      silver,
      bronze,
      row_number() OVER (
        PARTITION BY tag
        ORDER BY answers DESC, avg_answer_score DESC NULLS LAST
      ) AS tag_rank
    FROM tag_user
  )
SELECT
  tag,
  displayname,
  reputation,
  questions,
  answers,
  avg_answer_score,
  gold,
  silver,
  bronze,
  tag_rank
FROM rank_by_tag
WHERE tag_rank <= 3
ORDER BY tag, tag_rank;