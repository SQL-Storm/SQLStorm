-- {"query": "5096.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 708} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= now() - interval '90 days'
),
tag_popularity AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    COUNT(*) AS QuestionCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN recent_questions r ON p.Id = r.PostId
  GROUP BY TagName
),
top_tags AS (
  SELECT
    TagName,
    QuestionCount,
    TotalViews,
    AvgScore
  FROM tag_popularity
  ORDER BY TotalViews DESC
  LIMIT 20
),
complex_metrics AS (
  SELECT
    q.PostId,
    q.Title,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    u.DisplayName AS OwnerName,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.PostId) AS ChildCommentCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCountTotal,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 2) AS UpVotesForPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 3) AS DownVotesForPost,
    (SELECT JSON_AGG(JSON_BUILD_OBJECT('type', vt.Name, 'date', v.CreationDate)) 
       FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.PostId = q.PostId) AS VotesJson
  FROM recent_questions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
),
windowed AS (
  SELECT
    cm.*,
    dense_rank() OVER (ORDER BY cm.ViewCount DESC) AS ViewRank,
    dense_rank() OVER (ORDER BY cm.Score DESC) AS ScoreRank,
    SUM(cm.UpVotesForPost) OVER (ORDER BY cm.ViewCount DESC ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingUpVotes
  FROM complex_metrics cm
)
SELECT
  w.PostId,
  w.Title,
  w.OwnerName,
  w.ViewCount,
  w.Score,
  w.AnswerCount,
  w.CommentCount,
  w.FavoriteCount,
  w.ChildCommentCount,
  w.CommentCountTotal,
  w.UpVotesForPost,
  w.DownVotesForPost,
  w.VotesJson,
  w.ViewRank,
  w.ScoreRank,
  w.RollingUpVotes,
  (SELECT json_agg(t.TagName) FROM unnest(string_to_array(substr(w.Tags, 2, length(w.Tags) - 2), '><')) AS t(TagName)) AS SampleTags
FROM windowed w
ORDER BY w.ViewRank, w.ScoreRank
LIMIT 100;