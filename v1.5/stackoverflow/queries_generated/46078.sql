-- {"query": "46078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1682}

WITH RECURSIVE UserInfluence AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) as QuestionCount,
    COUNT(DISTINCT a.Id) as AnswerCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN a.PostTypeId = 2 THEN a.Score ELSE 0 END), 0) as AnswerScore
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
  LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
  WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TagExpertise AS (
  SELECT 
    ui.Id as UserId,
    string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array,
    AVG(p.Score) as avg_score,
    COUNT(*) as post_count
  FROM UserInfluence ui
  JOIN Posts p ON ui.Id = p.OwnerUserId
  WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
  GROUP BY ui.Id, p.Tags
),
TopAnswerers AS (
  SELECT 
    a.OwnerUserId,
    q.Tags,
    COUNT(*) as answer_count,
    AVG(a.Score) as avg_answer_score,
    COUNT(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 END) as accepted_count
  FROM Posts a
  JOIN Posts q ON a.ParentId = q.Id
  WHERE a.PostTypeId = 2 
    AND a.OwnerUserId IS NOT NULL
    AND q.PostTypeId = 1
    AND a.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
  GROUP BY a.OwnerUserId, q.Tags
  HAVING COUNT(*) >= 3
),
BadgeStats AS (
  SELECT 
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) as gold_badges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) as silver_badges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) as bronze_badges,
    COUNT(DISTINCT b.Name) as unique_badges
  FROM Badges b
  WHERE b.Date >= CURRENT_DATE - INTERVAL '2 years'
  GROUP BY b.UserId
),
VoteActivity AS (
  SELECT 
    p.OwnerUserId,
    COUNT(DISTINCT v.Id) as total_votes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as favorites
  FROM Votes v
  JOIN Posts p ON v.PostId = p.Id
  WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '18 months'
  GROUP BY p.OwnerUserId
),
CommentEngagement AS (
  SELECT 
    c.UserId,
    COUNT(*) as comment_count,
    AVG(c.Score) as avg_comment_score,
    COUNT(DISTINCT c.PostId) as unique_posts_commented
  FROM Comments c
  WHERE c.UserId IS NOT NULL 
    AND c.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
  GROUP BY c.UserId
  HAVING COUNT(*) > 20
)
SELECT 
  ui.Id,
  ui.DisplayName,
  ui.Reputation,
  EXTRACT(YEAR FROM AGE(CURRENT_DATE, ui.CreationDate)) as years_active,
  ui.QuestionCount,
  ui.AnswerCount,
  ui.QuestionScore + ui.AnswerScore as TotalScore,
  COALESCE(bs.gold_badges, 0) as GoldBadges,
  COALESCE(bs.silver_badges, 0) as SilverBadges,
  COALESCE(bs.bronze_badges, 0) as BronzeBadges,
  COALESCE(va.upvotes, 0) as ReceivedUpvotes,
  COALESCE(va.downvotes, 0) as ReceivedDownvotes,
  COALESCE(va.favorites, 0) as TimesBookmarked,
  COALESCE(ce.comment_count, 0) as CommentsPosted,
  COALESCE(ce.avg_comment_score, 0) as AvgCommentScore,
  COALESCE(ta.answer_count, 0) as SpecializedAnswers,
  COALESCE(ta.accepted_count, 0) as AcceptedAnswers,
  ROUND(CAST(COALESCE(ta.accepted_count, 0) AS NUMERIC) / NULLIF(COALESCE(ta.answer_count, 0), 0) * 100, 2) as AcceptanceRate,
  (ui.QuestionScore + ui.AnswerScore + COALESCE(bs.gold_badges, 0) * 50 + 
   COALESCE(bs.silver_badges, 0) * 25 + COALESCE(bs.bronze_badges, 0) * 10 +
   COALESCE(ta.accepted_count, 0) * 15) as InfluenceScore
FROM UserInfluence ui
LEFT JOIN BadgeStats bs ON ui.Id = bs.UserId
LEFT JOIN VoteActivity va ON ui.Id = va.OwnerUserId
LEFT JOIN CommentEngagement ce ON ui.Id = ce.UserId
LEFT JOIN TopAnswerers ta ON ui.Id = ta.OwnerUserId
WHERE (ui.QuestionScore + ui.AnswerScore) > 100
  AND ui.Reputation > 1000
ORDER BY InfluenceScore DESC, ui.Reputation DESC, TotalScore DESC
LIMIT 500;
