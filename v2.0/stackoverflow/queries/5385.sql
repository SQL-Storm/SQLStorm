-- {"query": "5385.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 974}
WITH
recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.ParentId,
    p.Body
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
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
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS rn_by_location
  FROM Users u
  WHERE u.Reputation > 1000
),
qualified_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
  FROM Votes v
  WHERE v.VoteTypeId IN (2,3,10,12,14,15,16)
),
linked AS (
  SELECT
    PL.PostId,
    PL.RelatedPostId,
    PL.LinkTypeId,
    T1.Name AS LinkTypeName
  FROM PostLinks PL
  JOIN LinkTypes T1 ON PL.LinkTypeId = T1.Id
  WHERE PL.LinkTypeId IN (1,3)
),
tag_excerpts AS (
  SELECT
    T.TagName,
    T.Count,
    T.ExcerptPostId,
    T.WikiPostId
  FROM Tags T
  WHERE T.IsModeratorOnly = FALSE AND T.IsRequired = FALSE
),
complex_score AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount AS Views,
    rp.AnswerCount,
    rp.CommentCount,
    rp.LastActivityDate,
    rp.Body,
    COALESCE(vt.TotalUp, 0) - COALESCE(vt.TotalDown, 0) AS NetScore
  FROM recent_posts rp
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId IN (2) THEN 1 ELSE 0 END) AS TotalUp,
      SUM(CASE WHEN VoteTypeId IN (3) THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes
    GROUP BY PostId
  ) vt ON rp.Id = vt.PostId
),
final AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.CreationDate,
    c.Score,
    c.Views,
    c.AnswerCount,
    c.CommentCount,
    c.LastActivityDate,
    c.Body,
    c.NetScore,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    ARRAY_AGG(DISTINCT cl.RelatedPostId) FILTER (WHERE cl.RelatedPostId IS NOT NULL) AS LinkedPostIds,
    ARRAY_AGG(DISTINCT te.TagName) FILTER (WHERE te.TagName IS NOT NULL) AS TagsList,
    ROW_NUMBER() OVER (ORDER BY c.NetScore DESC, c.Views DESC) AS rn
  FROM complex_score c
  LEFT JOIN Users u ON c.OwnerUserId = u.Id
  LEFT JOIN linked cl ON cl.PostId = c.PostId
  LEFT JOIN tag_excerpts te ON te.ExcerptPostId = c.PostId
  GROUP BY
    c.PostId, c.Title, c.OwnerUserId, c.CreationDate, c.Score, c.Views,
    c.AnswerCount, c.CommentCount, c.LastActivityDate, c.Body, c.NetScore,
    u.DisplayName, u.Reputation
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerUserId,
  f.OwnerDisplayName,
  f.Reputation,
  f.CreationDate,
  f.Score,
  f.Views,
  f.AnswerCount,
  f.CommentCount,
  f.LastActivityDate,
  f.Body,
  f.NetScore,
  f.LinkedPostIds,
  f.TagsList
FROM final f
WHERE f.rn <= 100
ORDER BY f.NetScore DESC, f.Views DESC, f.CreationDate DESC;