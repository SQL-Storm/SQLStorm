-- {"query": "5665.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 990}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.AccountId,
    AVG(p.Score) OVER (
      ORDER BY p.CreationDate
      ROWS BETWEEN 99 PRECEDING AND CURRENT ROW
    ) AS rolling_avg_score,
    RANK() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC
    ) AS score_rank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days')
),
correlated_sub AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Body,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.OwnerUserId,
    rp.LastEditorUserId,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.PostTypeId,
    rp.Reputation,
    rp.OwnerDisplayName,
    rp.Location,
    rp.Views,
    rp.UpVotes,
    rp.DownVotes,
    rp.ProfileImageUrl,
    rp.AccountId,
    rp.rolling_avg_score,
    rp.score_rank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountFromComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpModCount
  FROM ranked_posts rp
),
pivoted AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.Body,
    cs.CreationDate,
    cs.Score,
    cs.ViewCount,
    cs.Tags,
    cs.OwnerUserId,
    cs.LastEditorUserId,
    cs.LastActivityDate,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.PostTypeId,
    cs.Reputation,
    cs.OwnerDisplayName,
    cs.Location,
    cs.Views,
    cs.UpVotes,
    cs.DownVotes,
    cs.ProfileImageUrl,
    cs.AccountId,
    cs.rolling_avg_score,
    cs.score_rank,
    cs.CommentCountFromComments,
    cs.UpModCount,
    CONCAT(
      CASE WHEN cs.Score > 0 THEN 'Positive'
           WHEN cs.Score = 0 THEN 'Neutral'
           ELSE 'Negative' END,
      ' | ',
      'Owner=', COALESCE(cs.OwnerDisplayName, 'Unknown'),
      ' | ',
      'Tags=', COALESCE(cs.Tags, '')
    ) AS MetaDescriptor
  FROM correlated_sub cs
),
with_links AS (
  SELECT
    pvt.PostId,
    pvt.Title,
    pvt.Body,
    pvt.CreationDate,
    pvt.Score,
    pvt.ViewCount,
    pvt.Tags,
    pvt.OwnerUserId,
    pvt.LastEditorUserId,
    pvt.LastActivityDate,
    pvt.CommentCount,
    pvt.FavoriteCount,
    pvt.PostTypeId,
    pvt.Reputation,
    pvt.OwnerDisplayName,
    pvt.Location,
    pvt.Views,
    pvt.UpVotes,
    pvt.DownVotes,
    pvt.ProfileImageUrl,
    pvt.AccountId,
    pvt.rolling_avg_score,
    pvt.score_rank,
    pvt.CommentCountFromComments,
    pvt.UpModCount,
    pvt.MetaDescriptor,
    pl.RelatedPostId,
    rl.Id AS RelatedPostIdFromLink,
    (SELECT t.TagName
     FROM Tags t
     WHERE (t.WikiPostId = rl.Id OR t.ExcerptPostId = rl.Id)
     ORDER BY t.Count DESC
     FETCH FIRST 1 ROW ONLY) AS TagName
  FROM pivoted pvt
  LEFT JOIN PostLinks pl ON pl.PostId = pvt.PostId
  LEFT JOIN Posts rl ON rl.Id = pl.RelatedPostId
),
final_select AS (
  SELECT
    wl.PostId,
    wl.Title,
    wl.Body,
    wl.CreationDate,
    wl.Score,
    wl.ViewCount,
    wl.Tags,
    wl.OwnerUserId,
    wl.LastEditorUserId,
    wl.LastActivityDate,
    wl.CommentCount,
    wl.FavoriteCount,
    wl.PostTypeId,
    wl.Reputation,
    wl.OwnerDisplayName,
    wl.Location,
    wl.Views,
    wl.UpVotes,
    wl.DownVotes,
    wl.ProfileImageUrl,
    wl.AccountId,
    wl.rolling_avg_score,
    wl.score_rank,
    wl.CommentCountFromComments,
    wl.UpModCount,
    wl.MetaDescriptor,
    wl.RelatedPostId,
    wl.RelatedPostIdFromLink,
    wl.TagName,
    CASE
      WHEN wl.Score >= 10 OR wl.ViewCount >= 1000 THEN TRUE
      WHEN LOWER(wl.Title) LIKE '%performance%' OR LOWER(wl.Body) LIKE '%benchmark%' THEN TRUE
      ELSE FALSE
    END AS IncludeFlag
  FROM with_links wl
)
SELECT
  DISTINCT
  fs.PostId,
  fs.Title,
  fs.CreationDate,
  fs.Score,
  fs.ViewCount,
  fs.OwnerDisplayName,
  fs.Location,
  fs.rolling_avg_score AS rolling_avg_score_overall,
  fs.score_rank,
  fs.CommentCountFromComments,
  fs.UpModCount,
  fs.MetaDescriptor,
  fs.RelatedPostId,
  fs.TagName
FROM final_select fs
WHERE fs.IncludeFlag = TRUE
ORDER BY fs.Score DESC, fs.ViewCount DESC, fs.CreationDate DESC
FETCH FIRST 100 ROWS ONLY;