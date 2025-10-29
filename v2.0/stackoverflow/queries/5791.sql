-- {"query": "5791.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 968} 
WITH prod AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastEditDate,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.ProfileImageUrl,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    -- window: running total of views by day for this post's lifetime (simplified)
    SUM(p.ViewCount) OVER (PARTITION BY p.Id ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViews
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
recent AS (
  SELECT
    pr.PostId,
    pr.Title,
    pr.CreationDate,
    pr.ViewCount,
    pr.OwnerUserId,
    pr.OwnerDisplayName,
    pr.Reputation,
    pr.Location,
    pr.ProfileImageUrl,
    pr.Tags,
    pr.Body,
    ROW_NUMBER() OVER (
      PARTITION BY pr.OwnerUserId
      ORDER BY pr.CreationDate DESC
    ) AS rn
  FROM prod pr
  WHERE pr.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
enriched AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerDisplayName,
    r.Reputation,
    r.Location,
    r.ProfileImageUrl,
    r.Tags,
    r.Body,
    r.rn,
    -- correlated subquery: count of comments for the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId) AS CommentCountForPost,
    -- correlated subquery: number of votes of type UpMod (2)
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 2) AS UpModCount
  FROM recent r
),
joined AS (
  SELECT
    e.PostId,
    e.Title,
    e.CreationDate,
    e.ViewCount,
    e.OwnerUserId,
    e.OwnerDisplayName,
    e.Reputation,
    e.Location,
    e.ProfileImageUrl,
    e.Tags,
    e.Body,
    e.rn,
    e.CommentCountForPost,
    e.UpModCount
  FROM enriched e
  LEFT JOIN PostLinks pl ON pl.PostId = e.PostId
  LEFT JOIN Posts linked ON pl.RelatedPostId = linked.Id
),
final AS (
  SELECT
    j.PostId,
    j.Title,
    j.CreationDate,
    j.ViewCount,
    j.OwnerUserId,
    j.OwnerDisplayName,
    j.Reputation,
    j.Location,
    j.ProfileImageUrl,
    j.Tags,
    j.Body,
    j.rn,
    j.CommentCountForPost,
    j.UpModCount,
    -- compute a composite score using a window over the linked posts' view counts
    AVG(COALESCE(linked.ViewCount, 0)) OVER (PARTITION BY j.PostId) AS AvgLinkedViews,
    -- create a string expression with tagged counts and reputation bands
    CASE
      WHEN j.Reputation >= 10000 THEN 'Elite'
      WHEN j.Reputation >= 1000 THEN 'Top'
      WHEN j.Reputation >= 100 THEN 'Rising'
      ELSE 'New'
    END AS ReputationBand,
    -- NULL-sensitive calculation: 1 if Tags contains a specific tag, else 0
    CASE
      WHEN strpos(j.Tags, '<' || 'sql' || '>') > 0 THEN 1 ELSE 0 END AS HasSqlTag
  FROM joined j
  LEFT JOIN Posts linked ON j.PostId = linked.ParentId
)
SELECT
  PostId,
  Title,
  CreationDate,
  ViewCount,
  OwnerUserId,
  OwnerDisplayName,
  Reputation,
  Location,
  ProfileImageUrl,
  Tags,
  Body,
  rn AS RankWithinAuthor180,
  CommentCountForPost,
  UpModCount,
  AvgLinkedViews,
  ReputationBand,
  HasSqlTag
FROM final
WHERE rn <= 5
ORDER BY ReputationBand, CreationDate DESC
;