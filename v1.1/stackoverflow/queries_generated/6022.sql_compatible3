WITH
recent_user_activity AS (
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
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
top_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.FavoriteCount,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.Body,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.ContentLicense,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
      WHEN u.DisplayName IS NULL THEN 'Unknown'
      ELSE u.DisplayName
    END AS OwnerDisplayNameLookup
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2,3,4,5)
),
tag_derived AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptPostId,
    t.WikiPostId,
    pgc.PostId
  FROM Tags t
  LEFT JOIN LATERAL (
    SELECT p.Id AS PostId
    FROM Posts p
    WHERE p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
    LIMIT 1
  ) pgc ON true
),
linked_relations AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked', 'Duplicate')
),
vote_summary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN 1 ELSE 0 END) AS BountyCloses,
    COUNT(*) AS VoteCount
  FROM Votes v
  GROUP BY v.PostId
),
stateful_flags AS (
  SELECT
    p.Id AS PostId,
    MAX(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS IsDeleted,
    MAX(CASE WHEN v.VoteTypeId = 14 THEN 1 ELSE 0 END) AS IsModerated,
    MAX(CASE WHEN v.VoteTypeId = 16 THEN 1 ELSE 0 END) AS IsEditedByModerator
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
),
complex_expression AS (
  SELECT
    p.Id,
    p.Title,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    CASE
      WHEN p.Tags IS NOT NULL THEN
        COALESCE(
          (SELECT COUNT(*) FROM UNNEST(string_to_array(regexp_replace(p.Tags, '^<|>$', ''), '><')) AS t(x)),
          0
        )
      ELSE 0
    END AS TagCount
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  rp.PostId,
  rp.OwnerUserId AS UserId,
  rp.Title AS QuestionTitle,
  rp.Tags,
  rp.PostTypeId,
  rp.CreationDate AS PostCreationDate,
  rp.LastActivityDate AS PostLastActivity,
  rp.Score AS PostScore,
  rp.ViewCount,
  rp.CommentCount,
  rp.AnswerCount,
  rp.OwnerDisplayName,
  rp.OwnerDisplayNameLookup,
  ra.UserId AS ReporterUserId,
  ra.DisplayName AS ReporterName,
  ra.Reputation,
  ra.CreationDate AS ReporterCreationDate,
  ra.LastAccessDate AS ReporterLastAccessDate,
  ra.Location AS ReporterLocation,
  ts.PostId AS ts_PostId,
  ts.UpVotes AS PostUpVotes,
  ts.DownVotes AS PostDownVotes,
  ts.BountyStarts,
  ts.BountyCloses,
  fs.IsDeleted,
  fs.IsModerated,
  fs.IsEditedByModerator,
  cf.TagCount,
  bl.LinkTypeName,
  bl.RelatedPostId,
  bl.PostId AS LinkedPostId,
  vsc.PostId AS vsc_PostId,
  vsc.VoteCount,
  vsc.AcceptedVotes AS TotalUpVotes,
  vsc.UpVotes AS vsc_UpVotes,
  vsc.DownVotes AS TotalDownVotes
FROM top_posts rp
LEFT JOIN recent_user_activity ra ON rp.OwnerUserId = ra.UserId AND ra.rn = 1
LEFT JOIN vote_summary ts ON rp.PostId = ts.PostId
LEFT JOIN stateful_flags fs ON rp.PostId = fs.PostId
LEFT JOIN complex_expression cf ON rp.PostId = cf.Id
LEFT JOIN linked_relations bl ON rp.PostId = bl.PostId
LEFT JOIN (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(*) AS VoteCount
  FROM Votes v
  GROUP BY v.PostId
) vsc ON rp.PostId = vsc.PostId
WHERE
  rp.PostTypeId IN (1,2)
  AND (rp.Score > 0 OR rp.ViewCount > 100)
  AND (
    rp.Tags IS NULL
    OR position(
      '<' || (SELECT Name FROM PostHistoryTypes WHERE Id = 1) || '>' IN rp.Tags
    ) = 0
  )
GROUP BY
  rp.PostId,
  rp.OwnerUserId,
  rp.Title,
  rp.Tags,
  rp.PostTypeId,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.CommentCount,
  rp.AnswerCount,
  rp.OwnerDisplayName,
  rp.OwnerDisplayNameLookup,
  ra.UserId,
  ra.DisplayName,
  ra.Reputation,
  ra.CreationDate,
  ra.LastAccessDate,
  ra.Location,
  ts.PostId,
  ts.UpVotes,
  ts.DownVotes,
  ts.BountyStarts,
  ts.BountyCloses,
  fs.IsDeleted,
  fs.IsModerated,
  fs.IsEditedByModerator,
  cf.TagCount,
  bl.LinkTypeName,
  bl.RelatedPostId,
  bl.PostId,
  vsc.PostId,
  vsc.VoteCount,
  vsc.AcceptedVotes,
  vsc.UpVotes,
  vsc.DownVotes
ORDER BY rp.CreationDate DESC
LIMIT 100;