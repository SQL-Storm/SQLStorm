WITH UserPostStats AS (
  SELECT p.OwnerUserId,
         COUNT(*) AS num_posts,
         AVG(p.Score) AS avg_score,
         SUM(p.Score) AS total_score,
         SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_answers_count
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
  GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
  SELECT b.UserId,
         COUNT(*) AS num_badges,
         SUM(CASE WHEN b.Class = 1 THEN 10 WHEN b.Class = 2 THEN 5 ELSE 1 END) AS badge_points,
         SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS tag_based_badges
  FROM Badges b
  GROUP BY b.UserId
),
UserVoteStats AS (
  SELECT v.UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes_given,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes_given,
         SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS total_bounty_offered
  FROM Votes v
  GROUP BY v.UserId
),
UserCommentStats AS (
  SELECT c.UserId,
         COUNT(*) AS comments_made,
         AVG(c.Score) AS avg_comment_score
  FROM Comments c
  GROUP BY c.UserId
),
UserLinkStats AS (
  SELECT p.OwnerUserId,
         COUNT(DISTINCT COALESCE(pl.Id, pl.RelatedPostId)) AS questions_linked
  FROM Posts p
  JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId
)
SELECT u.DisplayName,
       u.Reputation,
       ups.num_posts,
       ups.avg_score,
       ups.total_score,
       ups.accepted_answers_count,
       ubs.num_badges,
       ubs.badge_points,
       ubs.tag_based_badges,
       uvs.up_votes_given,
       uvs.down_votes_given,
       uvs.total_bounty_offered,
       ucs.comments_made,
       ucs.avg_comment_score,
       uls.questions_linked,
       ROW_NUMBER() OVER (ORDER BY (COALESCE(ups.total_score,0) + COALESCE(ubs.badge_points,0) + COALESCE(uvs.up_votes_given,0) - COALESCE(uvs.down_votes_given,0) + COALESCE(ups.accepted_answers_count,0) * 10) DESC) AS activity_rank
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN UserVoteStats uvs ON u.Id = uvs.UserId
LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
LEFT JOIN UserLinkStats uls ON u.Id = uls.OwnerUserId
WHERE COALESCE(ups.num_posts, 0) > 5
GROUP BY u.DisplayName,
         u.Reputation,
         u.Id,
         ups.num_posts,
         ups.avg_score,
         ups.total_score,
         ups.accepted_answers_count,
         ubs.num_badges,
         ubs.badge_points,
         ubs.tag_based_badges,
         uvs.up_votes_given,
         uvs.down_votes_given,
         uvs.total_bounty_offered,
         ucs.comments_made,
         ucs.avg_comment_score,
         uls.questions_linked
ORDER BY activity_rank
LIMIT 50;