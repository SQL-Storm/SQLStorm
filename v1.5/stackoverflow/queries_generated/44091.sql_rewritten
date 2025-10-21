-- {"query": "44091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 208754, "output_tokens": 70923} 
WITH top_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation, COUNT(b.Id) AS badge_count
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id, u.DisplayName, u.Reputation
  ORDER BY badge_count DESC
  LIMIT 10
),
top_questions AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.AnswerCount, p.FavoriteCount, p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 1
  ORDER BY p.FavoriteCount DESC, p.AnswerCount DESC, p.CreationDate DESC
  LIMIT 10
),
top_tags AS (
  SELECT t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
  FROM Tags t
  ORDER BY t.Count DESC
  LIMIT 10
)
SELECT
  tu.DisplayName AS top_user_name,
  tu.Reputation AS top_user_reputation,
  tu.badge_count AS top_user_badges,
  tq.Title AS top_question_title,
  tq.OwnerUserId AS top_question_owner,
  tq.AnswerCount AS top_question_answers,
  tq.FavoriteCount AS top_question_favorites,
  tq.CreationDate AS top_question_created,
  tt.TagName AS top_tag_name,
  tt.Count AS top_tag_count,
  tt.ExcerptPostId AS top_tag_excerpt,
  tt.WikiPostId AS top_tag_wiki
FROM top_users tu
CROSS JOIN top_questions tq
CROSS JOIN top_tags tt
ORDER BY tu.badge_count DESC, tq.FavoriteCount DESC, tt.Count DESC
LIMIT 1;