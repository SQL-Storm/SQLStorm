-- {"query": "289.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10803} 
WITH
base AS (
  SELECT p.Id AS PostId,
         p.Title,
         COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
         COALESCE(u.Reputation, 0) AS Reputation,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.LastActivityDate,
         p.LastEditorDisplayName,
         p.OwnerUserId,
         (EXISTS (SELECT 1 FROM Badges bb WHERE bb.UserId = p.OwnerUserId AND bb.Class = 1)) AS HasGoldBadge
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
expanded AS (
  SELECT b.PostId, b.Title, b.OwnerName, b.Reputation, b.CreationDate, b.Score, b.ViewCount, b.Tags,
         COALESCE(
           (SELECT STRING_AGG(a.TagName, ',')
            FROM unnest(string_to_array(substring(b.Tags,2, length(b.Tags)-2), '><')) AS a(TagName)
           ),
           ''
         ) AS TagList,
         b.LastActivityDate, b.LastEditorDisplayName, b.OwnerUserId, b.HasGoldBadge
  FROM base b
),
metrics AS (
  SELECT e.PostId, e.Title, e.OwnerName, e.Reputation, e.CreationDate, e.Score, e.ViewCount, e.TagList,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 2) AS Upvotes,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 3) AS Downvotes,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = e.PostId) AS CommentCount,
         e.LastActivityDate, e.LastEditorDisplayName, e.OwnerUserId, e.HasGoldBadge,
         (SELECT COUNT(*) FROM Badges bb WHERE bb.UserId = e.OwnerUserId AND bb.Class = 1) AS OwnerBadgeCount
  FROM expanded e
),
q1 AS (
  SELECT p.PostId, p.Title, p.OwnerName, p.Reputation, p.CreationDate, p.Score, p.ViewCount, p.TagList,
         p.Upvotes, p.Downvotes, p.CommentCount, p.LastActivityDate, p.LastEditorDisplayName, p.OwnerBadgeCount, p.HasGoldBadge,
         (p.Title || ' by ' || COALESCE(p.OwnerName, 'Unknown') || ' ' || to_char(p.CreationDate, 'YYYY-MM-DD HH24:MI')) AS Summary,
         (p.Upvotes * 2 - p.Downvotes + p.CommentCount) AS EngagementScore,
         ROW_NUMBER() OVER (ORDER BY (p.Upvotes * 2 - p.Downvotes + p.CommentCount) DESC, p.LastActivityDate DESC) AS RankWithinSet
  FROM metrics p
  WHERE p.Upvotes > 50 AND p.LastActivityDate > now() - interval '365 days'
),
q2 AS (
  SELECT p.PostId, p.Title, p.OwnerName, p.Reputation, p.CreationDate, p.Score, p.ViewCount, p.TagList,
         p.Upvotes, p.Downvotes, p.CommentCount, p.LastActivityDate, p.LastEditorDisplayName, p.OwnerBadgeCount, p.HasGoldBadge,
         (p.Title || ' by ' || COALESCE(p.OwnerName, 'Unknown') || ' ' || to_char(p.CreationDate, 'YYYY-MM-DD HH24:MI')) AS Summary,
         (p.Upvotes * 2 - p.Downvotes + p.CommentCount) AS EngagementScore,
         ROW_NUMBER() OVER (ORDER BY (p.Upvotes * 2 - p.Downvotes + p.CommentCount) DESC, p.LastActivityDate DESC) AS RankWithinSet
  FROM metrics p
  WHERE p.Upvotes <= 50 AND p.LastActivityDate > now() - interval '365 days'
)
SELECT * FROM q1
UNION ALL
SELECT * FROM q2
ORDER BY EngagementScore DESC, RankWithinSet
LIMIT 100;