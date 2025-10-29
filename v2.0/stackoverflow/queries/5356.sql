-- {"query": "5356.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 780} 
WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
),
Enriched AS (
  SELECT
    tp.*,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = tp.PostId) AS AnswerCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tp.PostId) AS CommentCountFromComments,
    (SELECT STRING_AGG(vt.Name, ',') FROM Votes v
       JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
       WHERE v.PostId = tp.PostId AND v.VoteTypeId IN (2,3)) AS VoteSummary -- Up/Down interactions
  FROM TopPosts tp
),
HotTags AS (
  SELECT
    e.PostId,
    e.Title,
    e.OwnerDisplayName,
    e.Reputation,
    e.ViewCount,
    e.Score,
    e.CreationDate,
    e.LastActivityDate,
    e.Tags,
    CASE
      WHEN e.Tags ~ '\\<(.*)\\>' THEN regexp_split_to_table(e.Tags, '\\><')
      ELSE NULL
    END AS tag_split
  FROM Enriched e
),
Agg AS (
  SELECT
    e.PostId,
    e.Title,
    e.OwnerDisplayName,
    e.Reputation,
    e.ViewCount,
    e.Score,
    e.CreationDate,
    e.LastActivityDate,
    e.Tags,
    e.CommentCount,
    e.FavoriteCount,
    e.VoteSummary,
    COUNT(DISTINCT z.Id) AS RelatedPostCount
  FROM Enriched e
  LEFT JOIN PostLinks z ON z.PostId = e.PostId
  GROUP BY
    e.PostId, e.Title, e.OwnerDisplayName, e.Reputation, e.ViewCount, e.Score,
    e.CreationDate, e.LastActivityDate, e.Tags, e.CommentCount, e.FavoriteCount, e.VoteSummary
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerDisplayName,
  a.Reputation,
  a.ViewCount,
  a.Score,
  a.CreationDate,
  a.LastActivityDate,
  a.Tags,
  a.CommentCount,
  a.FavoriteCount,
  a.VoteSummary,
  a.RelatedPostCount,
  (a.Score * 1.0 / NULLIF(a.ViewCount, 0)) AS ScorePerView,
  (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS AvgQuestionScore,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.PostId AND v.VoteTypeId = 2) AS UpModCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.PostId AND v.VoteTypeId = 3) AS DownModCount,
  (SELECT MIN(CreationDate) FROM Votes v WHERE v.PostId = a.PostId AND v.VoteTypeId = 2) AS FirstUpvoteDate
FROM Agg a
ORDER BY a.LastActivityDate DESC, a.Reputation DESC
LIMIT 100;