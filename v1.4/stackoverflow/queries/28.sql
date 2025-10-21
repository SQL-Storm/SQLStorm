WITH recent_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY
),
top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe
  FROM Users u
  WHERE u.Reputation > 1000
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '14' DAY
),
recent_comments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId,
    c.UserDisplayName,
    c.Text,
    c.CreationDate
  FROM Comments c
  WHERE c.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '14' DAY
),
tag_aggregates AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE t.IsModeratorOnly = CAST(0 AS BOOLEAN)
  GROUP BY t.TagName
),
complex_post_metrics AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.OwnerUserId,
    tu.DisplayName AS OwnerDisplayName,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.PostTypeId,
    -- correlate with recent edits history via PostHistory (latest edit)
    (SELECT ph.CreationDate
     FROM PostHistory ph
     WHERE ph.PostId = rp.Id
       AND ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,14,15,16)
     ORDER BY ph.CreationDate DESC
     LIMIT 1) AS LastEditDate,
    -- window function: rank posts by activity within same day
    ROW_NUMBER() OVER (
      PARTITION BY DATE(rp.CreationDate)
      ORDER BY rp.ViewCount DESC, rp.Score DESC
    ) AS DayRank
  FROM recent_posts rp
  LEFT JOIN top_users tu ON rp.OwnerUserId = tu.Id
  WHERE rp.PostTypeId = 1 -- Questions
    AND rp.ViewCount > 0
),
combined AS (
  SELECT
    cmp.Id,
    cmp.Title,
    cmp.OwnerUserId,
    cmp.OwnerDisplayName,
    cmp.CreationDate,
    cmp.LastActivityDate,
    cmp.Score,
    cmp.ViewCount,
    cmp.Tags,
    cmp.DayRank,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM recent_votes rv
        WHERE rv.PostId = cmp.Id
          AND rv.VoteTypeId = 2 -- UpMod
          AND rv.UserId IN (SELECT Id FROM top_users)
      ) THEN TRUE
      ELSE FALSE
    END AS HasRecentUpvoteFromTopUsers,
    CASE
      WHEN (SELECT COUNT(*) FROM recent_comments rc WHERE rc.PostId = cmp.Id) > 0 THEN TRUE
      ELSE FALSE
    END AS HasRecentComment
  FROM complex_post_metrics cmp
),
final AS (
  SELECT
    c.Id,
    c.Title,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.CreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.Tags,
    c.DayRank,
    c.HasRecentUpvoteFromTopUsers,
    c.HasRecentComment,
    -- string expression: generate a pseudo tag summary
    (SELECT STRING_AGG(t.TagName, ', ' ORDER BY t.TagName)
     FROM UNNEST(string_to_array(REPLACE(REPLACE(REPLACE(c.Tags, '<', ''), '>', ''), ',', ' '), ' ')) AS t(TagName)
     WHERE t.TagName <> '') AS TagSummary
  FROM combined c
)
SELECT
  f.Id,
  f.Title,
  f.OwnerUserId,
  f.OwnerDisplayName,
  f.CreationDate,
  f.LastActivityDate,
  f.Score,
  f.ViewCount,
  f.Tags,
  f.DayRank,
  f.HasRecentUpvoteFromTopUsers,
  f.HasRecentComment,
  f.TagSummary
FROM final f
WHERE f.DayRank <= 10
ORDER BY f.LastActivityDate DESC, f.Score DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;