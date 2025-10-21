-- {"query": "52062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 864} 
WITH user_post_stats AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(p.Id) AS PostCount,
           SUM(p.Score) AS TotalScore,
           AVG(p.Score) AS AvgScore,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate >= '2010-01-01'
    GROUP BY p.OwnerUserId
),
user_vote_stats AS (
    SELECT v.UserId,
           COUNT(v.Id) AS TotalVotes,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
           SUM(CASE WHEN vt.Id = 4 THEN 1 ELSE 0 END) AS OffensiveCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL AND v.CreationDate >= '2010-01-01'
    GROUP BY v.UserId
),
user_badge_stats AS (
    SELECT b.UserId,
           COUNT(b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 10 WHEN b.Class = 2 THEN 5 ELSE 1 END) AS BadgeScore,
           MAX(CASE WHEN b.Name = 'Gold' THEN 1 ELSE 0 END) AS HasGoldBadge
    FROM Badges b
    WHERE b.Date >= '2010-01-01'
    GROUP BY b.UserId
),
user_comment_stats AS (
    SELECT c.UserId,
           COUNT(c.Id) AS CommentCount,
           SUM(c.Score) AS CommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL AND c.CreationDate >= '2010-01-01'
    GROUP BY c.UserId
),
ranked_users AS (
    SELECT u.Id,
           u.Reputation,
           u.CreationDate,
           ups.PostCount,
           ups.TotalScore,
           ups.AvgScore,
           ups.QuestionCount,
           ups.AnswerCount,
           uvs.TotalVotes,
           uvs.UpvoteCount,
           uvs.DownvoteCount,
           uvs.OffensiveCount,
           ubs.BadgeCount,
           ubs.BadgeScore,
           ubs.HasGoldBadge,
           ucs.CommentCount,
           ucs.CommentScore,
           (COALESCE(ups.TotalScore, 0) + COALESCE(ubs.BadgeScore, 0) + COALESCE(ucs.CommentScore, 0) * 0.1) / NULLIF(COALESCE(ups.PostCount, 0) + 1, 0) AS InfluenceScore
    FROM Users u
    LEFT JOIN user_post_stats ups ON u.Id = ups.UserId
    LEFT JOIN user_vote_stats uvs ON u.Id = uvs.UserId
    LEFT JOIN user_badge_stats ubs ON u.Id = ubs.UserId
    LEFT JOIN user_comment_stats ucs ON u.Id = ucs.UserId
    WHERE u.Reputation > 1000 AND ups.AnswerCount > 0
),
final_ranking AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY InfluenceScore DESC, Reputation DESC) AS GlobalRank
    FROM ranked_users
    WHERE InfluenceScore > 0
)
SELECT fr.Id AS UserId,
       fr.Reputation,
       fr.CreationDate,
       fr.PostCount,
       fr.TotalScore,
       fr.AvgScore,
       fr.QuestionCount,
       fr.AnswerCount,
       fr.TotalVotes,
       fr.UpvoteCount,
       fr.DownvoteCount,
       fr.OffensiveCount,
       fr.BadgeCount,
       fr.BadgeScore,
       fr.HasGoldBadge,
       fr.CommentCount,
       fr.CommentScore,
       fr.InfluenceScore,
       fr.GlobalRank
FROM final_ranking fr
ORDER BY fr.GlobalRank
LIMIT 100;