-- {"query": "4700.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1267} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  ),
  UserPostEngagement AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS total_posts_owned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
      SUM(p.Score) AS total_score_received,
      COUNT(DISTINCT c.Id) AS comment_count,
      COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvote_count,
      COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvote_count,
      MAX(p.CreationDate) AS last_post_creation_date
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserEditActivity AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS distinct_posts_edited,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS title_edits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS body_edits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS tag_edits,
      MAX(rpe.CreationDate) AS last_edit_date
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
  )
SELECT
  COALESCE(u.DisplayName, 'Unknown User') AS user_display_name,
  u.Reputation,
  u.Views AS profile_views,
  COALESCE(upe.total_posts_owned, 0) AS total_posts_owned,
  COALESCE(upe.question_count, 0) AS questions_asked,
  COALESCE(upe.answer_count, 0) AS answers_given,
  COALESCE(upe.total_score_received, 0) AS total_score_on_posts,
  COALESCE(upe.comment_count, 0) AS comments_made,
  COALESCE(upe.upvote_count, 0) AS upvotes_received,
  COALESCE(upe.downvote_count, 0) AS downvotes_received,
  COALESCE(uea.distinct_posts_edited, 0) AS distinct_posts_edited,
  COALESCE(uea.title_edits, 0) AS title_edit_count,
  COALESCE(uea.body_edits, 0) AS body_edit_count,
  COALESCE(uea.tag_edits, 0) AS tag_edit_count,
  CASE
    WHEN upe.last_post_creation_date IS NULL AND uea.last_edit_date IS NULL THEN 'Never Active'
    WHEN upe.last_post_creation_date IS NULL THEN 'Only Edited'
    WHEN uea.last_edit_date IS NULL THEN 'Only Posted'
    ELSE
      CASE
        WHEN upe.last_post_creation_date > uea.last_edit_date THEN 'Posted More Recently'
        ELSE 'Edited More Recently'
      END
  END AS recent_activity_type,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(u.WebsiteUrl)) > 0 THEN 'Has Website'
    ELSE 'No Website'
  END AS has_website_flag,
  CASE
    WHEN u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 0 AND LENGTH(u.AboutMe) > 200 THEN 'About Me Present (Long)'
    WHEN u.AboutMe IS NOT NULL AND LENGTH(TRIM(u.AboutMe)) > 0 THEN 'About Me Present (Short)'
    ELSE 'No About Me'
  END AS about_me_status,
  DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS reputation_rank
FROM Users AS u
LEFT JOIN UserPostEngagement AS upe
  ON u.Id = upe.OwnerUserId
LEFT JOIN UserEditActivity AS uea
  ON u.Id = uea.UserId
WHERE
  u.Id <= 1000000 /* Limit to a reasonable subset for benchmarking */
  AND (
    upe.total_posts_owned > 10 OR uea.distinct_posts_edited > 5
  ) /* Filter for users with some level of activity */
ORDER BY
  reputation_rank,
  u.CreationDate;
