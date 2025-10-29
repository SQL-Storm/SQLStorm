-- {"query": "5870.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1045} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.CommunityOwnedDate,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        CASE WHEN p.ViewCount IS NULL THEN 0 ELSE p.ViewCount END DESC,
        CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END DESC,
        p.CreationDate ASC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Posts r ON p.ParentId = r.Id
  WHERE p.PostTypeId IN (1,2,4,5) -- focus on questions, answers, and certain tag wiki types
),
ComplexFilters AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.Body,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.CommunityOwnedDate,
    rp.ContentLicense,
    (CASE
       WHEN rp.LastEditorUserId IS NULL THEN 0
       ELSE 1
     END) AS HasRecentEditor,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = rp.PostId
        AND v.VoteTypeId = 2
        AND v.CreationDate > rp.LastActivityDate - INTERVAL '30 days'
    ) AS HasRecentUpvote,
    (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = rp.PostId AND v2.VoteTypeId = 2) AS TotalUpvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS TotalComments,
    (CASE
       WHEN rp.Tags IS NOT NULL THEN
         (SELECT SUM(tag_count) FROM unnest(string_to_array(rp.Tags, '><')) AS tag_count)
       ELSE 0
     END) AS TagTokenCount
  FROM RankedPosts rp
  WHERE rp.rn_by_type = 1
    OR rp.PostTypeId = 1 -- include some older style heavy posts
),
WindowAgg AS (
  SELECT
    cf.*,
    MAX(cf.TotalUpvotes) OVER () AS MaxUpvotesAllPosts,
    MIN(cf.CreationDate) OVER () AS EarliestCreation,
    SUM(cf.TotalUpvotes) OVER () AS SumUpvotesAll
  FROM ComplexFilters cf
),
Final AS (
  SELECT
    wa.PostId,
    wa.PostTypeId,
    wa.Title,
    wa.OwnerUserId,
    wa.OwnerDisplayName,
    wa.Reputation,
    wa.CreationDate,
    wa.LastActivityDate,
    wa.Score,
    wa.ViewCount,
    wa.Tags,
    wa.AnswerCount,
    wa.CommentCount,
    wa.FavoriteCount,
    wa.Body,
    wa.ParentId,
    wa.AcceptedAnswerId,
    wa.LastEditorUserId,
    wa.LastEditDate,
    wa.CommunityOwnedDate,
    wa.ContentLicense,
    wa.HasRecentEditor,
    wa.HasRecentUpvote,
    wa.TotalUpvotes,
    wa.TotalComments,
    wa.TagTokenCount,
    wa.MaxUpvotesAllPosts,
    wa.EarliestCreation,
    wa.SumUpvotesAll,
    -- Complex predicates and calculated expressions
    (CASE
       WHEN wa.PostTypeId = 1 AND wa.AnswerCount IS NOT NULL THEN wa.AnswerCount * 2
       WHEN wa.PostTypeId = 2 THEN wa.Score * -1
       ELSE wa.ViewCount
     END) AS EngagementScore,
    (CASE
       WHEN wa.OwnerUserId IS NULL THEN NULL
       ELSE CAST(wa.OwnerUserId AS VARCHAR(20))
     END) AS OwnerUserIdStr,
    (CASE
       WHEN wa.LastEditorUserId IS NOT NULL THEN true
       ELSE false
     END) AS HadLastEditor
  FROM WindowAgg wa
)
SELECT *
FROM Final
ORDER BY EngagementScore DESC NULLS LAST, LastActivityDate DESC
LIMIT 200;