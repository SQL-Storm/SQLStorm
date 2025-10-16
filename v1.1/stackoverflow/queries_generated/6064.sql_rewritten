-- {"query": "6064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1026} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ParentId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
top_tag_interactions AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    p.Id AS post_id
  FROM Posts p
  JOIN recent_questions rq ON p.Id = rq.PostId
),
tag_stats AS (
  SELECT
    tag,
    COUNT(*) AS questions_with_tag
  FROM top_tag_interactions
  GROUP BY tag
),
tag_pagerank AS (
  SELECT
    tag,
    questions_with_tag,
    ROW_NUMBER() OVER (ORDER BY questions_with_tag DESC, tag ASC) AS rn
  FROM tag_stats
),
recent_comments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Score,
    c.Text,
    c.CreationDate
  FROM Comments c
  WHERE c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '14 days'
),
post_scores AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.Tags,
    p.PostTypeId,
    p.ParentId,
    COALESCE(vt.max_vote, 0) AS MaxVoteType,
    COALESCE(v.Amount, 0) AS BountyAmount
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, MAX(VoteTypeId) AS max_vote
    FROM Votes
    GROUP BY PostId
  ) vt ON vt.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, SUM(COALESCE(BountyAmount,0)) AS Amount
    FROM Votes
    WHERE VoteTypeId = 8
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
complex_predicate AS (
  SELECT
    ps.*,
    CASE
      WHEN ps.ViewCount > 1000 THEN TRUE
      WHEN ps.Score > 10 AND ps.CommentCount > 5 THEN TRUE
      ELSE FALSE
    END AS HighlyVisible,
    CASE
      WHEN ps.OwnerUserId IS NULL THEN 'anonymous' ELSE 'registered' END AS UserCategory
  FROM post_scores ps
),
windowed AS (
  SELECT
    cp.*,
    LAG(cp.LastActivityDate) OVER (PARTITION BY cp.ParentId ORDER BY cp.LastActivityDate) AS PrevActivity
  FROM complex_predicate cp
),
final AS (
  SELECT
    w.PostId,
    w.Title,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    w.CommentCount,
    w.AnswerCount,
    w.Tags,
    w.PostTypeId,
    w.ParentId,
    w.MaxVoteType,
    w.BountyAmount,
    w.HighlyVisible,
    w.UserCategory,
    CASE
      WHEN w.ParentId IS NULL THEN 'Question'
      ELSE 'Answer'
    END AS PostKind,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = w.PostId) AS CommentCountTotal
  FROM windowed w
),
join_chart AS (
  SELECT
    f.*,
    rt.rn AS TagRank
  FROM final f
  LEFT JOIN top_tag_interactions tti ON tti.post_id = f.PostId
  LEFT JOIN tag_pagerank rt ON rt.tag = tti.tag
)
SELECT
  j.PostId,
  j.Title,
  j.OwnerDisplayName AS DisplayName,
  j.CreationDate,
  j.LastActivityDate,
  j.Score,
  j.ViewCount,
  j.CommentCount AS LocalCommentCount,
  j.AnswerCount,
  j.Tags,
  j.PostTypeId,
  j.ParentId,
  j.MaxVoteType,
  j.BountyAmount,
  j.HighlyVisible,
  j.UserCategory,
  j.PostKind,
  j.CommentCountTotal,
  COALESCE(j.TagRank, 9999) AS TagRank
FROM join_chart j
ORDER BY j.LastActivityDate DESC, j.Score DESC
LIMIT 200;