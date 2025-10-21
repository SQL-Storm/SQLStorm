-- {"query": "52053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 706} 
WITH TagScores AS (
  SELECT 
    string_to_array(substring(Tags, 2, length(Tags)-2), '><') as TagArray,
    AVG(p.Score) as AvgScore,
    COUNT(p.Id) as PostCount,
    SUM(p.ViewCount) as TotalViews
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  GROUP BY string_to_array(substring(Tags, 2, length(Tags)-2), '><')
),
AnswerStats AS (
  SELECT 
    ap.ParentId,
    COUNT(ap.Id) as AnswerCount,
    SUM(ap.Score) as TotalAnswerScore,
    AVG(ap.Score) as AvgAnswerScore,
    COUNT(CASE WHEN ap.Score > 10 THEN 1 END) as HighScoreAnswers
  FROM Posts ap
  WHERE ap.PostTypeId = 2
  GROUP BY ap.ParentId
),
UserActivity AS (
  SELECT 
    u.Id,
    u.Reputation,
    COUNT(DISTINCT p.Id) as QuestionCount,
    SUM(p.Score) as TotalQuestionScore,
    COUNT(DISTINCT b.Id) as BadgeCount,
    COUNT(DISTINCT c.Id) as CommentCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.Reputation
),
VoteHistory AS (
  SELECT 
    v.PostId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as Upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as Downvotes,
    COUNT(CASE WHEN v.VoteTypeId = 1 THEN 1 END) as AcceptedVotes
  FROM Votes v
  GROUP BY v.PostId
)
SELECT 
  q.Id,
  q.Title,
  q.Score as QuestionScore,
  q.ViewCount,
  ast.TotalAnswerScore,
  ast.AvgAnswerScore,
  ast.HighScoreAnswers,
  vh.Upvotes,
  vh.Downvotes,
  vh.AcceptedVotes,
  ua.Reputation,
  ua.QuestionCount,
  ua.BadgeCount,
  ua.CommentCount,
  ROW_NUMBER() OVER (
    PARTITION BY (SELECT unnest(ts.TagArray) FROM TagScores ts LIMIT 1)
    ORDER BY (q.Score + ast.TotalAnswerScore + vh.Upvotes - vh.Downvotes) DESC
  ) as RankWithinTag
FROM Posts q
INNER JOIN AnswerStats ast ON ast.ParentId = q.Id
INNER JOIN VoteHistory vh ON vh.PostId = q.Id
INNER JOIN UserActivity ua ON ua.Id = q.OwnerUserId
CROSS JOIN TagScores ts
WHERE q.PostTypeId = 1
  AND q.AcceptedAnswerId IS NOT NULL
  AND q.ClosedDate IS NULL
  AND q.CreationDate >= '2020-01-01'
  AND ts.PostCount > 1000
  AND q.Score > 5
  AND ast.AnswerCount > 5
ORDER BY (q.Score + ast.TotalAnswerScore + vh.Upvotes - vh.Downvotes) DESC
LIMIT 100;