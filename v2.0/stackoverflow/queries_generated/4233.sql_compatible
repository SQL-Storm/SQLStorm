WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS total_posts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
      AVG(p.Score) AS average_score,
      MAX(p.ViewCount) AS max_view_count,
      SUM(p.FavoriteCount) AS total_favorites
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  TagWisdom AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS tag_post_count,
      SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END) AS total_answers_on_questions_with_tag,
      AVG(p.Score) AS avg_score_for_tag
    FROM Tags t
    LEFT JOIN Posts p
      ON POSITION(',' || t.TagName || ',' IN COALESCE(',' || p.Tags || ',', ',')) > 0
    WHERE
      t.TagName NOT LIKE '%-%'
    GROUP BY
      t.TagName
  ),
  UserContributionScore AS (
    SELECT
      upa.OwnerUserId,
      (
        upa.total_posts * 1.0
        + upa.question_count * 5.0
        + upa.answer_count * 3.0
        + COALESCE(upa.average_score, 0) * 1.5
        + COALESCE(upa.max_view_count, 0) * 0.1
        + upa.total_favorites * 2.0
      ) AS contribution_score
    FROM UserPostActivity upa
  ),
  HighReputationUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      DATE_PART('year', AGE(TIMESTAMP '2024-10-01 12:34:56', u.CreationDate)) AS account_age_years,
      COUNT(DISTINCT b.Id) AS badge_count
    FROM Users u
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    WHERE
      u.Reputation > 10000
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
    HAVING
      COUNT(DISTINCT b.Id) > 5
  )
SELECT
  COALESCE(hr.DisplayName, 'Anonymous') AS user_display_name,
  hr.Reputation,
  hr.account_age_years,
  hr.badge_count,
  COALESCE(ucs.contribution_score, 0) AS calculated_contribution_score,
  (
    SELECT
      COUNT(*)
    FROM Posts p
    WHERE
      p.OwnerUserId = hr.Id AND p.ClosedDate IS NOT NULL
  ) AS closed_post_count,
  (
    SELECT
      SUM(COALESCE(p.CommentCount, 0))
    FROM Posts p
    WHERE
      p.OwnerUserId = hr.Id
  ) AS total_comments_made,
  (
    SELECT
      COUNT(DISTINCT rpe.PostId)
    FROM RankedPostEdits rpe
    WHERE
      rpe.UserId = hr.Id AND rpe.rn = 1
  ) AS posts_last_edited_by_user,
  CASE
    WHEN hr.DisplayName LIKE '%a%' AND hr.Reputation > 50000 THEN 'Highly Engaged Contributor'
    WHEN hr.Reputation BETWEEN 10000 AND 50000 THEN 'Experienced Member'
    ELSE 'Established User'
  END AS user_tier,
  (
    SELECT
      AVG(post_score_rank)
    FROM (
      SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.Score,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS post_score_rank
      FROM Posts p
      WHERE
        p.OwnerUserId = hr.Id AND p.PostTypeId = 1
    ) AS UserPostRanks
  ) AS avg_question_score_rank,
  (
    SELECT
      COUNT(*)
    FROM PostHistory ph
    WHERE
      ph.UserId = hr.Id AND ph.PostHistoryTypeId IN (1, 2, 3)
  ) AS initial_post_creations,
  (
    SELECT
      COUNT(*)
    FROM PostHistory ph
    WHERE
      ph.UserId = hr.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS post_edits,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.UserId = hr.Id AND c.Score > 5
  ) AS high_score_comment_count
FROM HighReputationUsers hr
LEFT JOIN UserContributionScore ucs
  ON hr.Id = ucs.OwnerUserId
ORDER BY
  hr.Reputation DESC
LIMIT 100;