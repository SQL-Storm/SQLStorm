WITH
  _cte_user_post_metrics AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS post_count,
      SUM(p.Score) AS total_score,
      AVG(p.Score) AS avg_score,
      MAX(p.CreationDate) AS latest_post_date,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
      SUM(p.ViewCount) AS total_views,
      SUM(CASE WHEN p.AnswerCount IS NOT NULL THEN 1 ELSE 0 END) AS posts_with_answers
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  _cte_user_comment_metrics AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS comment_count,
      SUM(c.Score) AS total_comment_score,
      AVG(c.Score) AS avg_comment_score
    FROM
      Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  _cte_user_vote_metrics AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvote_count,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvote_count,
      COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorite_count,
      COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) AS bounty_start_count
    FROM
      Votes AS v
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  _cte_user_badge_metrics AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badge_count,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badge_count,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badge_count,
      MAX(b.Date) AS latest_badge_date
    FROM
      Badges AS b
    GROUP BY
      b.UserId
  ),
  _cte_user_contribution_summary AS (
    SELECT
      COALESCE(upm.OwnerUserId, ccm.UserId, cvm.UserId) AS UserId,
      COALESCE(upm.post_count, 0) AS total_posts,
      COALESCE(upm.total_score, 0) AS total_post_score,
      COALESCE(upm.avg_score, 0) AS average_post_score,
      COALESCE(upm.question_count, 0) AS total_questions,
      COALESCE(upm.answer_count, 0) AS total_answers,
      COALESCE(upm.posts_with_answers, 0) AS posts_with_answers,
      COALESCE(upm.total_views, 0) AS total_post_views,
      COALESCE(upm.latest_post_date, TIMESTAMP '1970-01-01') AS latest_activity_date,
      COALESCE(ccm.comment_count, 0) AS total_comments,
      COALESCE(ccm.total_comment_score, 0) AS total_comment_score,
      COALESCE(ccm.avg_comment_score, 0) AS average_comment_score,
      COALESCE(cvm.upvote_count, 0) AS total_upvotes,
      COALESCE(cvm.downvote_count, 0) AS total_downvotes,
      COALESCE(cvm.favorite_count, 0) AS total_favorites,
      COALESCE(cvm.bounty_start_count, 0) AS total_bounty_starts,
      COALESCE(ubm.gold_badge_count, 0) AS total_gold_badges,
      COALESCE(ubm.silver_badge_count, 0) AS total_silver_badges,
      COALESCE(ubm.bronze_badge_count, 0) AS total_bronze_badges,
      COALESCE(ubm.latest_badge_date, TIMESTAMP '1970-01-01') AS latest_badge_earned_date
    FROM
      _cte_user_post_metrics AS upm
    FULL OUTER JOIN
      _cte_user_comment_metrics AS ccm
      ON upm.OwnerUserId = ccm.UserId
    FULL OUTER JOIN
      _cte_user_vote_metrics AS cvm
      ON COALESCE(upm.OwnerUserId, ccm.UserId) = cvm.UserId
    FULL OUTER JOIN
      _cte_user_badge_metrics AS ubm
      ON COALESCE(upm.OwnerUserId, ccm.UserId, cvm.UserId) = ubm.UserId
  )
SELECT
  u.DisplayName,
  uc.total_posts,
  uc.total_post_score,
  uc.average_post_score,
  uc.total_questions,
  uc.total_answers,
  uc.posts_with_answers,
  uc.total_post_views,
  uc.latest_activity_date,
  uc.total_comments,
  uc.total_comment_score,
  uc.average_comment_score,
  uc.total_upvotes,
  uc.total_downvotes,
  uc.total_favorites,
  uc.total_bounty_starts,
  uc.total_gold_badges,
  uc.total_silver_badges,
  uc.total_bronze_badges,
  uc.latest_badge_earned_date,
  u.Reputation,
  u.CreationDate AS user_creation_date,
  u.Views AS user_views_profile,
  u.UpVotes AS user_profile_upvotes,
  u.DownVotes AS user_profile_downvotes,
  CASE
    WHEN uc.total_posts > 0 THEN ROUND(CAST(uc.total_post_score AS NUMERIC) / uc.total_posts, 2)
    ELSE 0
  END AS overall_post_score_per_post,
  CASE
    WHEN uc.total_comments > 0 THEN ROUND(CAST(uc.total_comment_score AS NUMERIC) / uc.total_comments, 2)
    ELSE 0
  END AS overall_comment_score_per_comment,
  CASE
    WHEN uc.total_questions > 0 THEN CAST(uc.total_answers AS NUMERIC) / uc.total_questions
    ELSE 0
  END AS answer_to_question_ratio,
  CASE
    WHEN uc.total_posts > 0 AND uc.total_post_views > 0 THEN ROUND(CAST(uc.total_post_views AS NUMERIC) / uc.total_posts, 2)
    ELSE 0
  END AS average_views_per_post,
  CASE
    WHEN uc.total_gold_badges > 0 THEN CAST(EXTRACT(YEAR FROM uc.latest_badge_earned_date) AS VARCHAR)
    ELSE 'N/A'
  END AS year_of_last_gold_badge,
  CASE
    WHEN u.DisplayName LIKE '%expert%' OR u.DisplayName LIKE '%guru%' THEN 'Professional'
    WHEN u.DisplayName LIKE '%newbie%' OR u.DisplayName LIKE '%beginner%' THEN 'Novice'
    WHEN u.Location IS NOT NULL AND LENGTH(u.Location) > 10 THEN 'Has Detailed Location'
    WHEN uc.total_upvotes > 1000 THEN 'Highly Voted'
    ELSE 'Standard'
  END AS user_category,
  CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website' ELSE 'No Website' END AS website_status,
  CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 'Has Detailed Bio' ELSE 'Brief or No Bio' END AS bio_length_category,
  CASE WHEN uc.total_post_views > u.Views * 10 THEN 'High External Engagement' ELSE 'Standard Engagement' END AS engagement_comparison,
  pht.Name AS latest_post_history_type_name,
  ph.Comment AS latest_post_history_comment,
  ph.CreationDate AS latest_post_history_date
FROM
  Users AS u
LEFT OUTER JOIN
  _cte_user_contribution_summary AS uc
  ON u.Id = uc.UserId
LEFT OUTER JOIN
  PostHistory AS ph
  ON u.Id = ph.UserId
LEFT OUTER JOIN
  PostHistoryTypes AS pht
  ON ph.PostHistoryTypeId = pht.Id
WHERE
  u.Id IN (
    SELECT
      p2.OwnerUserId
    FROM
      Posts AS p2
    WHERE
      p2.PostTypeId = 1
    UNION
    SELECT
      c2.UserId
    FROM
      Comments AS c2
    WHERE
      c2.UserId IS NOT NULL
  )
  AND u.Id NOT IN (SELECT b2.UserId FROM Badges AS b2 WHERE b2.Name = 'Autobiographer')
  AND (uc.total_questions > 5 OR uc.total_answers > 10)
  AND uc.average_post_score > 0.5
  AND uc.latest_activity_date > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
  AND (
    ph.PostHistoryTypeId IN (4, 5, 6)
    OR ph.PostHistoryTypeId IN (10, 11)
    OR ph.PostHistoryTypeId IN (19, 20)
  )
  AND EXISTS (
    SELECT
      1
    FROM
      PostLinks AS pl
      JOIN Posts AS p3 ON pl.PostId = p3.Id
    WHERE
      pl.LinkTypeId = 3
      AND p3.OwnerUserId = u.Id
  )
GROUP BY
  u.Id,
  u.DisplayName,
  uc.total_posts,
  uc.total_post_score,
  uc.average_post_score,
  uc.total_questions,
  uc.total_answers,
  uc.posts_with_answers,
  uc.total_post_views,
  uc.latest_activity_date,
  uc.total_comments,
  uc.total_comment_score,
  uc.average_comment_score,
  uc.total_upvotes,
  uc.total_downvotes,
  uc.total_favorites,
  uc.total_bounty_starts,
  uc.total_gold_badges,
  uc.total_silver_badges,
  uc.total_bronze_badges,
  uc.latest_badge_earned_date,
  u.Reputation,
  u.CreationDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.WebsiteUrl,
  u.AboutMe,
  u.Location,
  pht.Name,
  ph.Comment,
  ph.CreationDate
ORDER BY
  u.Reputation DESC,
  uc.latest_activity_date DESC
LIMIT 100;