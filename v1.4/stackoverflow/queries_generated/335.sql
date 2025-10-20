-- {"query": "335.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18539} 
WITH
  base AS (
    SELECT
      p.Id,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      COALESCE(u.DisplayName, p.OwnerDisplayName, '') AS OwnerName,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.LastActivityDate,
      p.LastEditDate,
      p.ParentId,
      p.AcceptedAnswerId,
      p.Tags,
      p.CommentCount AS PostCommentCount,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountFromComments,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesFromVotes,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotesFromVotes,
      (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkedPostCount,
      (SELECT COUNT(*) FROM Tags t WHERE t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id) AS TagRelatedCount,
      COALESCE(le.DisplayName, p.LastEditorDisplayName, '') AS LastEditorName
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Users le ON le.Id = p.LastEditorUserId
    WHERE p.PostTypeId IN (1, 2)
  ),
  scored AS (
    SELECT b.*,
           ROW_NUMBER() OVER (PARTITION BY b.PostTypeId ORDER BY b.Score DESC NULLS LAST, b.CreationDate DESC) AS rn
    FROM base b
  ),
  recent AS (
    SELECT s.*
    FROM scored s
    WHERE s.CreationDate >= now() - interval '30 days'
       OR s.LastActivityDate >= now() - interval '30 days'
  ),
  top_type AS (
    SELECT s.*
    FROM scored s
    WHERE s.rn = 1
  ),
  unioned AS (
    SELECT * FROM recent
    UNION ALL
    SELECT * FROM top_type
  ),
  badge_info AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount, MAX(b.Date) AS MostRecentBadgeDate
    FROM Badges b
    GROUP BY b.UserId
  ),
  last_history AS (
    SELECT hl.PostId,
           pht.Name AS HistoryTypeName,
           hl.Comment,
           hl.PostHistoryTypeId
    FROM (
      SELECT ph.PostId, ph.PostHistoryTypeId, ph.Comment, ph.CreationDate,
             ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
      FROM PostHistory ph
    ) hl
    LEFT JOIN PostHistoryTypes pht ON pht.Id = hl.PostHistoryTypeId
    WHERE hl.rn = 1
  )
SELECT
  c.Id,
  c.Title,
  c.PostTypeId,
  pt.Name AS PostTypeName,
  c.OwnerUserId,
  c.OwnerName,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.LastActivityDate,
  c.LastEditDate,
  c.ParentId,
  c.AcceptedAnswerId,
  c.Tags,
  c.PostCommentCount,
  c.CommentCountFromComments,
  c.UpVotesFromVotes,
  c.DownVotesFromVotes,
  c.LinkedPostCount,
  c.TagRelatedCount,
  c.LastEditorName,
  bi.BadgeCount AS OwnerBadgeCount,
  bi.MostRecentBadgeDate,
  lh.HistoryTypeName AS LastHistoryTypeName,
  lh.Comment AS LastHistoryComment,
  lh.PostHistoryTypeId AS LastHistoryTypeId,
  (c.Title || ' | ' || pt.Name) AS TitleWithType
FROM unioned c
LEFT JOIN PostTypes pt ON pt.Id = c.PostTypeId
LEFT JOIN badge_info bi ON bi.UserId = c.OwnerUserId
LEFT JOIN last_history lh ON lh.PostId = c.Id
ORDER BY c.Score DESC NULLS LAST, c.CreationDate DESC
LIMIT 400;