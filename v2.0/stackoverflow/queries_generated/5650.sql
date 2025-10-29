-- {"query": "5650.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1005} 
WITH
RecentHot AS (
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
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId
  FROM Users u
  WHERE u.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '180 days'
),
Combined AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.Tags,
    rh.CreationDate,
    rh.LastActivityDate,
    rh.Score,
    rh.ViewCount,
    rh.OwnerUserId,
    ru.UserId AS ActiveUserId,
    ru.DisplayName AS ActiveDisplayName,
    rh.CommentCount,
    rh.AnswerCount,
    rh.FavoriteCount,
    rh.PostTypeId,
    rh.rn_owner,
    EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rh.PostId AND pl.RelatedPostId = rh.PostId + 1
    ) AS SelfLinked
  FROM RecentHot rh
  LEFT JOIN ActiveUsers ru ON rh.OwnerUserId = RU.UserId
  WHERE rh.rn_owner = 1
),
StatWindow AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.LastActivityDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesFromPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesFromPost,
    AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBounty,
    COUNT(DISTINCT co.Id) AS CommentCountAll,
    COUNT(DISTINCT pa.Id) AS AnswerCountAll
  FROM Combined c
  LEFT JOIN Votes v ON v.PostId = c.PostId
  LEFT JOIN Comments co ON co.PostId = c.PostId
  LEFT JOIN Posts pa ON pa.ParentId = c.PostId
  GROUP BY c.PostId, c.Title, c.OwnerUserId, c.LastActivityDate
),
Final AS (
  SELECT
    s.PostId,
    s.Title,
    s.OwnerUserId,
    s.LastActivityDate,
    s.UpVotesFromPost,
    s.DownVotesFromPost,
    s.AvgBounty,
    s.CommentCountAll,
    s.AnswerCountAll,
    s.ActiveUserId,
    s.ActiveDisplayName,
    ROW_NUMBER() OVER (ORDER BY s.LastActivityDate DESC, s.UpVotesFromPost - s.DownVotesFromPost DESC NULLS LAST) AS rn_final
  FROM StatWindow s
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerUserId,
  f.LastActivityDate,
  f.UpVotesFromPost,
  f.DownVotesFromPost,
  f.AvgBounty,
  f.CommentCountAll,
  f.AnswerCountAll,
  f.ActiveUserId,
  f.ActiveDisplayName,
  (SELECT STRING_AGG(CONCAT(u.DisplayName, ' (', u.Reputation, ')'), ' | ')
   FROM Users u
   WHERE u.Id = f.OwnerUserId) AS OwnerProfileSummary,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = f.PostId) AS LinkCount,
  (SELECT ARRAY_AGG(t.TagName) FROM Tags t WHERE t.Id IN (
        SELECT unnest(string_to_array(f.Tags, '>') ) -- simulate tags parsing
  )) AS TagArray,
  f.rn_final
FROM Final f
WHERE f.rn_final = 1
ORDER BY f.LastActivityDate DESC, f.UpVotesFromPost DESC
LIMIT 50;