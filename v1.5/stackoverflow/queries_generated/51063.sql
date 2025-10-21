-- {"query": "51063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1169} 

WITH top_tags AS (
  SELECT TagName, Count
  FROM Tags
  WHERE Count > 1000
  ORDER BY Count DESC
  LIMIT 10
),
user_activity AS (
  SELECT u.Id AS UserId, u.Reputation, u.UpVotes, u.DownVotes,
         COUNT(DISTINCT p.Id) AS PostCount,
         SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
         SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
         AVG(p.Score) AS AvgPostScore,
         COUNT(DISTINCT v.PostId) AS TotalVotesReceived
  FROM Users u
  INNER JOIN Posts p ON p.OwnerUserId = u.Id 
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
  GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
  HAVING COUNT(DISTINCT p.Id) >= 50
),
tag_user_activity AS (
  SELECT tt.TagName,
         ua.UserId,
         SUM(CASE WHEN p.Tags LIKE '%' || tt.TagName || '%'
                  THEN 1 ELSE 0 END) AS TaggedPosts,
         AVG(CASE WHEN p.Tags LIKE '%' || tt.TagName || '%'
                  THEN p.Score ELSE 0 END) AS AvgTagScore
  FROM top_tags tt
  CROSS JOIN user_activity ua
  LEFT JOIN Posts p ON p.OwnerUserId = ua.UserId 
                     AND p.PostTypeId = 1 
                     AND p.CreationDate >= NOW() - INTERVAL '1 year'
  GROUP BY tt.TagName, ua.UserId
),
badge_stats AS (
  SELECT b.UserId,
         COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
         COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
         COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
         COUNT(DISTINCT b.Name) AS UniqueBadges
  FROM Badges b
  WHERE b.Date >= NOW() - INTERVAL '2 years'
  GROUP BY b.UserId
),
post_interactions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount,
         ph.PostHistoryTypeId,
         COUNT(DISTINCT ph.Id) AS HistoryCount,
         COUNT(DISTINCT c.Id) AS CommentCountActual,
         COUNT(DISTINCT pl.RelatedPostId) AS LinkCount,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
  WHERE p.PostTypeId = 1 
    AND p.CreationDate >= NOW() - INTERVAL '6 months'
    AND p.Score > 5
  GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, 
           p.CommentCount, p.FavoriteCount, ph.PostHistoryTypeId
)
SELECT 
  tt.TagName,
  ua.DisplayName AS UserName,
  ua.Reputation,
  ua.PostCount,
  ua.QuestionCount,
  ua.AnswerCount,
  tua.TaggedPosts,
  tua.AvgTagScore,
  COALESCE(bs.GoldBadges, 0) AS GoldBadges,
  COALESCE(bs.SilverBadges, 0) AS SilverBadges,
  ROUND(AVG(pi.Score) OVER (PARTITION BY tt.TagName), 2) AS AvgQuestionScoreByTag,
  ROUND(SUM(pi.UpVotes) OVER (PARTITION BY tt.TagName) / 
        NULLIF(COUNT(pi.UpVotes) OVER (PARTITION BY tt.TagName), 0), 2) AS AvgUpVotesPerQuestionByTag,
  COUNT(DISTINCT pi.PostId) AS HighScoringQuestions,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY pi.ViewCount) OVER (PARTITION BY tt.TagName) AS P90ViewCount
FROM top_tags tt
INNER JOIN tag_user_activity tua ON tua.TagName = tt.TagName
INNER JOIN user_activity ua ON ua.UserId = tua.UserId
LEFT JOIN badge_stats bs ON bs.UserId = ua.UserId
INNER JOIN post_interactions pi ON pi.PostId IN (
  SELECT p.Id 
  FROM Posts p 
  WHERE p.Tags LIKE '%' || tt.TagName || '%' 
    AND p.PostTypeId = 1 
    AND p.Score > 10
)
WHERE tua.TaggedPosts >= 5
GROUP BY tt.TagName, ua.DisplayName, ua.Reputation, ua.PostCount, 
         ua.QuestionCount, ua.AnswerCount, tua.TaggedPosts, tua.AvgTagScore,
         bs.GoldBadges, bs.SilverBadges
HAVING AVG(pi.ViewCount) > 1000
ORDER BY tt.Count DESC, ua.Reputation DESC
LIMIT 50;
