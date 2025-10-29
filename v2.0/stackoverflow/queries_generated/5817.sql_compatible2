WITH quenched AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    pv.VoteTypeId,
    pv.UserId AS VoterUserId,
    pv.CreationDate AS VoteDate,
    cu.DisplayName AS VoterDisplayName,
    c.Id AS CommentId,
    c.Text AS CommentText,
    c.CreationDate AS CommentDate
  FROM Posts p
  LEFT JOIN Votes pv
    ON pv.PostId = p.Id
  LEFT JOIN Users cu
    ON cu.Id = pv.UserId
  LEFT JOIN Comments c
    ON c.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
windowed AS (
  SELECT
    PostId,
    Title,
    Score,
    ViewCount,
    CreationDate,
    LastActivityDate,
    OwnerUserId,
    Tags,
    PostTypeId,
    VoteDate,
    VoterUserId,
    VoterDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY PostId
      ORDER BY VoteDate DESC
    ) AS rn_votes,
    CommentId,
    CommentText,
    CommentDate
  FROM quenched
),
aggregated AS (
  SELECT
    w.PostId,
    w.Title,
    w.Score,
    w.ViewCount,
    w.CreationDate,
    w.LastActivityDate,
    w.OwnerUserId,
    w.Tags,
    w.PostTypeId,
    MAX(w.VoteDate) AS LastVoteDate,
    MAX(CASE WHEN w.rn_votes = 1 THEN w.VoterUserId END) AS LastVoterUserId,
    MAX(CASE WHEN w.rn_votes = 1 THEN w.VoterDisplayName END) AS LastVoterDisplayName,
    MAX(w.CommentId) AS LatestCommentId,
    MAX(w.CommentDate) AS LatestCommentDate,
    MAX(w.CommentText) AS LatestCommentText
  FROM windowed w
  GROUP BY
    w.PostId,
    w.Title,
    w.Score,
    w.ViewCount,
    w.CreationDate,
    w.LastActivityDate,
    w.OwnerUserId,
    w.Tags,
    w.PostTypeId
),
joined AS (
  SELECT
    a.PostId,
    a.Title,
    a.Score,
    a.ViewCount,
    a.CreationDate,
    a.LastActivityDate,
    a.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    a.Tags,
    a.PostTypeId,
    a.LastVoteDate,
    a.LastVoterUserId,
    a.LastVoterDisplayName,
    a.LatestCommentId,
    a.LatestCommentDate,
    a.LatestCommentText,
    pl.Id AS LinkId,
    lt.Name AS LinkTypeName,
    b.Reputation AS OpponentReputation
  FROM aggregated a
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  LEFT JOIN Posts ld ON ld.OwnerUserId = a.OwnerUserId AND ld.PostTypeId = 2
  LEFT JOIN PostLinks pl ON pl.PostId = a.PostId
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN Posts pb ON pb.Id = pl.RelatedPostId
  LEFT JOIN Users b ON b.Id = pb.OwnerUserId
),
final AS (
  SELECT
    PostId,
    Title,
    Score,
    ViewCount,
    CreationDate,
    LastActivityDate,
    OwnerUserId,
    OwnerDisplayName,
    Tags,
    PostTypeId,
    LastVoteDate,
    LastVoterUserId,
    LastVoterDisplayName,
    LatestCommentId,
    LatestCommentDate,
    LatestCommentText,
    CASE
      WHEN PostTypeId = 1 THEN 'Question'
      WHEN PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    COALESCE(LOWER(REGEXP_REPLACE(Tags, '<|>|[ ]', '', 'g')), '') AS CleanTags,
    ('https://example.org/post/' || PostId) AS PostUrl
  FROM joined
)
SELECT
  PostId,
  Title,
  PostKind,
  Score,
  ViewCount,
  CreationDate,
  LastActivityDate,
  OwnerDisplayName,
  CleanTags,
  PostUrl,
  LastVoteDate,
  LastVoterDisplayName,
  LatestCommentDate,
  LatestCommentText
FROM final
WHERE
  (PostTypeId = 1 AND Score > 0)
  OR (PostTypeId = 2 AND ViewCount > 100)
ORDER BY LastActivityDate DESC
LIMIT 100;