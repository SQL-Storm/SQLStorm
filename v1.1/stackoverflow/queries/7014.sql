WITH
ParsedTags AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    COALESCE(p.Title, '') AS Title,
    COALESCE(p.Tags, '') AS RawTags,
    NULLIF(p.Tags, '') IS NOT NULL AS HasTags,
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN 0 ELSE (char_length(p.Tags) - char_length(replace(p.Tags, '<', ''))) END AS EstimatedTagCount,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId
  FROM Posts p
),
ExplodedTagsFix AS (
  SELECT
    pt2.PostId,
    trim(both ' ' FROM regexp_replace(u.tag, '[<>]', '', 'g')) AS Tag,
    pt2.PostTypeId,
    pt2.Title,
    pt2.CreationDate,
    pt2.Score,
    pt2.ViewCount,
    pt2.OwnerUserId
  FROM (
    SELECT
      pt.PostId,
      CASE
        WHEN pt.RawTags = '' THEN NULL
        ELSE regexp_split_to_array(substring(pt.RawTags FROM 2 FOR greatest(char_length(pt.RawTags)-2,0)), '><')
      END AS tags_arr,
      pt.PostTypeId,
      pt.Title,
      pt.CreationDate,
      pt.Score,
      pt.ViewCount,
      pt.OwnerUserId
    FROM ParsedTags pt
  ) pt2
  CROSS JOIN LATERAL (
    SELECT unnest(pt2.tags_arr) AS tag
  ) u
),
UserAgg AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.Location, '(unknown)') AS Location,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) OVER (PARTITION BY u.Id) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) OVER (PARTITION BY u.Id) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) OVER (PARTITION BY u.Id) AS BronzeBadges,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC NULLS LAST) AS LastBadgeRow,
    MAX(b.Date) OVER (PARTITION BY u.Id) AS LastBadgeDate
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
),
VoteMetrics AS (
  SELECT
    v.PostId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS BountyStarts,
    SUM(COALESCE(v.BountyAmount,0)) FILTER (WHERE v.VoteTypeId IN (8,9)) AS TotalBountyAmount,
    COUNT(*) AS TotalVotes,
    MIN(v.CreationDate) AS FirstVote,
    MAX(v.CreationDate) AS LastVote
  FROM Votes v
  GROUP BY v.PostId
),
LinkPairs AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkType,
    ROW_NUMBER() OVER (PARTITION BY pl.PostId, pl.RelatedPostId ORDER BY pl.CreationDate) AS LinkSeq
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
HistorySummary AS (
  SELECT
    ph.PostId,
    COUNT(*) AS Revisions,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS ContentEdits,
    MAX(ph.CreationDate) AS LastHistoryDate,
    (SELECT char_length(CAST(ph2.Text AS text))
     FROM PostHistory ph2
     WHERE ph2.PostId = ph.PostId AND ph2.Text IS NOT NULL
     ORDER BY ph2.CreationDate DESC
     LIMIT 1
    ) AS LastRevisionTextLength
  FROM PostHistory ph
  GROUP BY ph.PostId
),
ScoredPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    COALESCE(vm.UpVotes,0) AS UpVotes,
    COALESCE(vm.DownVotes,0) AS DownVotes,
    COALESCE(vm.TotalBountyAmount,0) AS TotalBounty,
    COALESCE(hs.Revisions,0) AS Revisions,
    COALESCE(hs.LastRevisionTextLength,0) AS LastRevLen,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate))/86400.0 AS AgeDays,
    (COALESCE(p.Score,0) * 1.5 + COALESCE(vm.UpVotes,0) * 1.0 - COALESCE(vm.DownVotes,0) * 1.2
      + LEAST(COALESCE(vm.TotalBountyAmount,0),1000) * 0.05
      + LEAST(COALESCE(hs.Revisions,0),50) * 0.3
      + GREATEST(0, 50 - EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate))/86400.0) * 0.2
    ) / (1 + GREATEST(1, EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate))/86400.0) * 0.01) AS CompositeScore
  FROM Posts p
  LEFT JOIN VoteMetrics vm ON vm.PostId = p.Id
  LEFT JOIN HistorySummary hs ON hs.PostId = p.Id
),
UserTopTags AS (
  SELECT
    et.OwnerUserId,
    et.Tag,
    COUNT(*) AS TagUses,
    RANK() OVER (PARTITION BY et.OwnerUserId ORDER BY COUNT(*) DESC, et.Tag) AS TagRank
  FROM ExplodedTagsFix et
  GROUP BY et.OwnerUserId, et.Tag
),
RankedCandidates AS (
  SELECT
    sp.Id AS PostId,
    sp.Title,
    sp.PostTypeId,
    sp.OwnerUserId,
    u.DisplayName AS OwnerName,
    sp.CreationDate,
    sp.Score,
    sp.CompositeScore,
    COALESCE(vm.UpVotes,0) AS UpVotes,
    COALESCE(vm.DownVotes,0) AS DownVotes,
    hs.Revisions,
    hs.LastRevisionTextLength,
    (SELECT string_agg(t.Tag, ', ' ORDER BY t.TagRank, t.Tag)
     FROM (
       SELECT Tag, TagRank FROM UserTopTags utt
       WHERE utt.OwnerUserId = sp.OwnerUserId AND utt.TagRank <= 3
     ) t
    ) AS TopTagsForOwner,
    (SELECT COUNT(*) FROM (
       SELECT LinkTypeId FROM PostLinks pl WHERE pl.PostId = sp.Id
       UNION
       SELECT LinkTypeId FROM PostLinks pl WHERE pl.RelatedPostId = sp.Id
    ) x) AS DistinctLinkTypesInvolved,
    EXISTS (
      SELECT 1 FROM PostLinks pl2 WHERE (pl2.PostId = sp.Id OR pl2.RelatedPostId = sp.Id) AND pl2.LinkTypeId = 3
    ) AS IsDuplicated,
    (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY CAST(a.Score AS numeric))
     FROM Posts a
     WHERE a.ParentId = sp.Id AND a.PostTypeId = 2
    ) AS MedianAnswerScore,
    (SELECT COUNT(*) FROM Comments c
     LEFT JOIN Users uc ON uc.Id = c.UserId
     WHERE c.PostId = sp.Id
       AND (c.Text IS NOT NULL AND char_length(c.Text) > 5)
       AND (uc.Id IS NOT NULL OR c.UserDisplayName IS NOT NULL)
    ) AS MeaningfulCommentCount
  FROM ScoredPosts sp
  LEFT JOIN Users u ON u.Id = sp.OwnerUserId
  LEFT JOIN VoteMetrics vm ON vm.PostId = sp.Id
  LEFT JOIN HistorySummary hs ON hs.PostId = sp.Id
  WHERE sp.PostTypeId = 1
),
FinalSelection AS (
  SELECT
    rc.PostId,
    rc.Title,
    rc.PostTypeId,
    rc.OwnerUserId,
    rc.OwnerName,
    rc.CreationDate,
    rc.Score,
    rc.CompositeScore,
    rc.UpVotes,
    rc.DownVotes,
    rc.Revisions,
    rc.LastRevisionTextLength,
    rc.TopTagsForOwner,
    rc.DistinctLinkTypesInvolved,
    rc.IsDuplicated,
    rc.MedianAnswerScore,
    rc.MeaningfulCommentCount,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(rc.OwnerUserId, -1) ORDER BY rc.CompositeScore DESC NULLS LAST, rc.MedianAnswerScore DESC NULLS LAST) AS OwnerRank,
    RANK() OVER (ORDER BY rc.CompositeScore DESC NULLS LAST, rc.Score DESC NULLS LAST) AS GlobalRank,
    NTILE(10) OVER (ORDER BY rc.CompositeScore DESC NULLS LAST) AS Decile
  FROM RankedCandidates rc
)
SELECT
  fs.GlobalRank,
  fs.PostId,
  fs.Title,
  fs.OwnerUserId,
  COALESCE(fs.OwnerName, '(deleted)') AS OwnerName,
  fs.CreationDate,
  fs.Score,
  ROUND(CAST(fs.CompositeScore AS numeric),2) AS CompositeScore,
  COALESCE(fs.UpVotes,0) AS UpVotes,
  COALESCE(fs.DownVotes,0) AS DownVotes,
  COALESCE(fs.Revisions,0) AS Revisions,
  COALESCE(fs.LastRevisionTextLength,0) AS LastRevisionTextLength,
  COALESCE(fs.MedianAnswerScore,0) AS MedianAnswerScore,
  COALESCE(fs.MeaningfulCommentCount,0) AS MeaningfulCommentCount,
  COALESCE(fs.TopTagsForOwner, '(none)') AS TopTagsForOwner,
  fs.IsDuplicated,
  fs.DistinctLinkTypesInvolved,
  fs.OwnerRank,
  fs.Decile
FROM FinalSelection fs
WHERE fs.Decile = 1
  AND fs.CompositeScore IS NOT NULL
  AND (fs.MeaningfulCommentCount > 0 OR fs.Revisions > 1)
ORDER BY fs.CompositeScore DESC, fs.MedianAnswerScore DESC, fs.Score DESC
LIMIT 250;