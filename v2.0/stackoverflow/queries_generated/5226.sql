-- {"query": "5226.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 758} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl
  FROM Users u
),
question_activity AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.OwnerUserId,
    rq.CreationDate AS QuestionCreated,
    rq.LastActivityDate,
    rq.Score AS QuestionScore,
    rq.ViewCount,
    rq.CommentCount,
    rq.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY rq.OwnerUserId ORDER BY rq.LastActivityDate DESC) AS rn
  FROM recent_questions rq
),
related_tags AS (
  SELECT
    qa.PostId,
    unnest(string_to_array(substr(qa.Tags, 2, length(qa.Tags)-2), '><')) AS TagName
  FROM question_activity qa
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(qa.QuestionScore) AS AvgQuestionScore
  FROM related_tags t
  JOIN question_activity qa ON qa.PostId = t.PostId
  GROUP BY t.TagName
),
popular_tags AS (
  SELECT
    TagName
  FROM tag_stats
  WHERE TagQuestionCount > 5
  ORDER BY AvgQuestionScore DESC
  LIMIT 10
),
final AS (
  SELECT
    qa.PostId,
    qa.Title,
    qa.OwnerUserId,
    cu.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    qa.QuestionCreated,
    qa.LastActivityDate,
    qa.QuestionScore,
    qa.ViewCount,
    qa.CommentCount,
    qa.AnswerCount,
    ARRAY_AGG(DISTINCT tt.TagName) FILTER (WHERE tt.TagName IS NOT NULL) AS TagsOnQuestion,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = qa.PostId
          AND v.VoteTypeId = 2
          AND v.UserId IS NOT NULL
      ) THEN true
      ELSE false
    END AS HasUpvoters
  FROM question_activity qa
  LEFT JOIN Users cu ON cu.Id = qa.OwnerUserId
  LEFT JOIN Users u ON u.Id = qa.OwnerUserId
  LEFT JOIN related_tags tt ON tt.PostId = qa.PostId
  WHERE EXISTS (SELECT 1 FROM popular_tags pt WHERE pt.TagName = ANY(ARRAY[qa.Tags]))
  GROUP BY qa.PostId, qa.Title, qa.OwnerUserId, cu.DisplayName, u.Reputation, qa.QuestionCreated, qa.LastActivityDate, qa.QuestionScore, qa.ViewCount, qa.CommentCount, qa.AnswerCount
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerDisplayName,
  f.OwnerReputation,
  f.QuestionCreated,
  f.LastActivityDate,
  f.QuestionScore,
  f.ViewCount,
  f.CommentCount,
  f.AnswerCount,
  f.TagsOnQuestion,
  f.HasUpvoters
FROM final f
ORDER BY f.LastActivityDate DESC
LIMIT 100;