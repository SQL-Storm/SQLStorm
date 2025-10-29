WITH RankedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn
  FROM
    Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM
    Tags t
  WHERE
    t.IsModeratorOnly = FALSE
),
RecentActivity AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment,
    ph.Text
  FROM
    PostHistory ph
  WHERE
    ph.PostHistoryTypeId IN (10,11,12,16,66)
),
JoinedActivity AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.LastActivityDate,
    q.AcceptedAnswerId,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    ra.PostHistoryTypeId AS ActivityType,
    ra.CreationDate AS ActivityDate,
    ra.UserDisplayName AS ActivityUser,
    q.rn
  FROM RankedQuestions q
  LEFT JOIN RecentActivity ra ON ra.PostId = q.PostId
  ORDER BY q.rn
),
CrossFiltered AS (
  SELECT
    j.PostId,
    j.Title,
    j.CreationDate,
    j.Score,
    j.ViewCount,
    j.OwnerUserId,
    j.OwnerDisplayName,
    j.LastActivityDate,
    j.AcceptedAnswerId,
    j.AnswerCount,
    j.CommentCount,
    j.FavoriteCount,
    j.ActivityType,
    j.ActivityDate,
    j.ActivityUser,
    j.rn
  FROM JoinedActivity j
  LEFT JOIN TopTags tt ON LOWER(j.Title) LIKE '%' || LOWER(tt.TagName) || '%'
  WHERE
    (j.LastActivityDate > j.CreationDate - INTERVAL '180 days')
    OR j.ActivityDate IS NOT NULL
),
TagAggregates AS (
  SELECT
    cf.PostId,
    STRING_AGG(tt.TagName, ',') AS TagList
  FROM CrossFiltered cf
  LEFT JOIN TopTags tt ON LOWER(cf.Title) LIKE '%' || LOWER(tt.TagName) || '%'
  GROUP BY cf.PostId
)
SELECT
  cf.PostId,
  cf.Title,
  cf.CreationDate,
  cf.Score,
  cf.ViewCount,
  cf.OwnerDisplayName,
  cf.LastActivityDate,
  cf.AcceptedAnswerId,
  cf.AnswerCount,
  cf.CommentCount,
  cf.FavoriteCount,
  cf.ActivityType,
  cf.ActivityDate,
  cf.ActivityUser,
  ta.TagList,
  (SELECT AVG(CAST(v.BountyAmount AS numeric)) FROM Votes v WHERE v.PostId = cf.PostId AND v.VoteTypeId = 8) AS AverageBounty
FROM
  CrossFiltered cf
  LEFT JOIN TagAggregates ta ON ta.PostId = cf.PostId
GROUP BY
  cf.PostId,
  cf.Title,
  cf.CreationDate,
  cf.Score,
  cf.ViewCount,
  cf.OwnerDisplayName,
  cf.LastActivityDate,
  cf.AcceptedAnswerId,
  cf.AnswerCount,
  cf.CommentCount,
  cf.FavoriteCount,
  cf.ActivityType,
  cf.ActivityDate,
  cf.ActivityUser,
  cf.rn,
  ta.TagList
ORDER BY
  cf.LastActivityDate DESC NULLS LAST
LIMIT 1000;