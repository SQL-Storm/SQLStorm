-- {"query": "6082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 651} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
tag_popularity AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
),
tag_aggregates AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgScore
  FROM tag_popularity t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY TagName
),
top_tags AS (
  SELECT
    TagName,
    PostCount,
    TotalScore,
    AvgScore,
    ROW_NUMBER() OVER (ORDER BY PostCount DESC, TotalScore DESC, AvgScore DESC) AS rn
  FROM tag_aggregates
),
users_rank AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    u.Location,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
)
SELECT
  rq.PostId,
  rq.Title,
  rq.Tags,
  rq.CreationDate AS PostCreationDate,
  rq.Score AS PostScore,
  rq.ViewCount,
  rq.OwnerDisplayName,
  rq.CommentCount,
  rq.AnswerCount,
  rq.FavoriteCount,
  rq.PostTypeId,
  jsonb_build_object(
    'TopTags', (
      SELECT jsonb_agg(jsonb_build_object('Tag', t.TagName, 'Posts', t.PostCount, 'TotalScore', t.TotalScore, 'AvgScore', t.AvgScore))
      FROM top_tags t
      WHERE t.rn <= 5
    ),
    'Owner', jsonb_build_object(
      'UserId', u.UserId,
      'DisplayName', u.DisplayName,
      'Reputation', u.Reputation
    )
  ) AS Meta
FROM recent_questions rq
LEFT JOIN (
  SELECT DISTINCT ON (PostId) PostId, TagName
  FROM tag_popularity
) tp ON tp.PostId = rq.PostId
LEFT JOIN Users u ON rq.OwnerUserId = u.Id
ORDER BY rq.CreationDate DESC
LIMIT 100;