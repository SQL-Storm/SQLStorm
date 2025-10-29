WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
TaggedActivity AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.Reputation,
    rp.ViewCount,
    rp.Tags,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.LastEditDate,
    rp.ContentLicense,
    CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END AS IsQuestion,
    COALESCE(tv.UpModCount, 0) AS UpModCount,
    COALESCE(tv.DownModCount, 0) AS DownModCount,
    COALESCE(bd.GoldCount, 0) AS GoldBadges,
    COALESCE(sd.SilverCount, 0) AS SilverBadges
  FROM RankedPosts rp
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount
    FROM Votes
    GROUP BY PostId
  ) tv ON rp.Id = tv.PostId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldCount
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
  ) bd ON rp.OwnerUserId = bd.UserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS SilverCount
    FROM Badges
    WHERE Class = 2
    GROUP BY UserId
  ) sd ON rp.OwnerUserId = sd.UserId
  WHERE rp.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
),
ComplexFilters AS (
  SELECT
    ta.Id,
    ta.Title,
    ta.PostTypeId,
    ta.OwnerUserId,
    ta.OwnerName,
    ta.Reputation,
    ta.ViewCount,
    ta.Tags,
    ta.AnswerCount,
    ta.CommentCount,
    ta.FavoriteCount,
    ta.CreationDate,
    ta.LastActivityDate,
    ta.LastEditDate,
    ta.ContentLicense,
    ta.IsQuestion,
    ta.UpModCount,
    ta.DownModCount,
    ta.GoldBadges,
    ta.SilverBadges,
    ta.DuplicateLinkCount,
    ta.OwnerPostRank
  FROM (
    SELECT
      ta.*,
      (
        SELECT COUNT(*) FROM PostLinks pl
        WHERE pl.PostId = ta.Id AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount,
      ROW_NUMBER() OVER (PARTITION BY ta.OwnerUserId ORDER BY ta.LastActivityDate DESC) AS OwnerPostRank
    FROM TaggedActivity ta
  ) ta
),
PerformanceBench AS (
  SELECT
    cf.Id,
    cf.Title,
    cf.PostTypeId,
    cf.OwnerUserId,
    cf.OwnerName,
    cf.Reputation,
    cf.ViewCount,
    cf.Tags,
    cf.AnswerCount,
    cf.CommentCount,
    cf.FavoriteCount,
    cf.CreationDate,
    cf.LastActivityDate,
    cf.LastEditDate,
    cf.ContentLicense,
    cf.IsQuestion,
    cf.UpModCount,
    cf.DownModCount,
    cf.GoldBadges,
    cf.SilverBadges,
    cf.DuplicateLinkCount,
    cf.OwnerPostRank,
    (cf.ViewCount * 0.5 + cf.AnswerCount * 30 + cf.UpModCount * 15 - cf.DownModCount * 5) AS EngagementScore,
    CASE
      WHEN cf.IsQuestion = 1 AND cf.AnswerCount > 0 THEN 'Question with answers'
      WHEN cf.IsQuestion = 0 THEN 'Answer or other'
      ELSE 'Other'
    END AS CategoryLabel,
    LOWER(REGEXP_REPLACE(cf.Title, '[^a-zA-Z0-9 ]', '', 'g')) AS NormalizedTitle
  FROM ComplexFilters cf
)
SELECT
  pb.Id,
  pb.Title,
  pb.PostTypeId,
  pb.OwnerUserId,
  pb.OwnerName,
  pb.Reputation,
  pb.ViewCount,
  pb.Tags,
  pb.AnswerCount,
  pb.CommentCount,
  pb.FavoriteCount,
  pb.CreationDate,
  pb.LastActivityDate,
  pb.LastEditDate,
  pb.ContentLicense,
  pb.IsQuestion,
  pb.UpModCount,
  pb.DownModCount,
  pb.GoldBadges,
  pb.SilverBadges,
  pb.DuplicateLinkCount,
  pb.OwnerPostRank,
  pb.EngagementScore,
  pb.CategoryLabel,
  pb.NormalizedTitle
FROM PerformanceBench pb
WHERE pb.EngagementScore > 100
ORDER BY pb.EngagementScore DESC
LIMIT 100
OFFSET 0;