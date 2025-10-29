-- {"query": "5182.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 796} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditDate,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.CreatedDate AS UserCreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    (SELECT COUNT(*) FROM Posts AS a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS ChildAnswerCount,
    (SELECT COUNT(*) FROM Comments AS c WHERE c.PostId = p.Id) AS CommentCountTotal
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- focus on Questions and Answers
),
RecentActivity AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.PostTypeId,
    rp.LastActivityDate,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.Body,
    rp.FavoriteCount,
    rp.Reputation,
    rp.DisplayName,
    rp.UserCreationDate,
    rp.LastAccessDate,
    rp.Location,
    rp.Views,
    rp.UpVotes,
    rp.DownVotes,
    rp.ProfileImageUrl,
    rp.ChildAnswerCount,
    rp.CommentCountTotal,
    ROW_NUMBER() OVER (
      PARTITION BY rp.OwnerUserId
      ORDER BY rp.LastActivityDate DESC, rp.Score DESC
    ) AS rn_by_author
  FROM RankedPosts rp
),
Aggregated AS (
  SELECT
    ra.Id,
    ra.Title,
    ra.PostTypeId,
    ra.OwnerUserId,
    ra.DisplayName,
    ra.UserCreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.Views,
    ra.Location,
    ra.Reputation,
    ra.UpVotes,
    ra.DownVotes,
    ra.Body,
    ra.Tags,
    ra.CommentCountTotal,
    ra.ChildAnswerCount,
    ra.FavoriteCount,
    ra.ProfileImageUrl,
    -- compute a complex string expression combining score, views, and reputation
    CONCAT(
      'S', CAST(ABS(ra.Score) AS varchar(10)),
      '|V', CAST(ra.ViewCount AS varchar(20)),
      '|R', CAST(ra.Reputation AS varchar(20))
    ) AS MetaKey,
    -- correlation subquery: average score of posts in the same tag group (approx)
    (SELECT AVG(p2.Score)
     FROM Posts p2
     WHERE p2.Tags && ra.Tags
       AND p2.PostTypeId = ra.PostTypeId
    ) AS AvgScoreSimilarTags
  FROM RecentActivity ra
  WHERE ra.rn_by_author = 1
)
SELECT
  a.Id,
  a.Title,
  a.PostTypeId,
  a.OwnerUserId,
  a.DisplayName,
  a.UserCreationDate,
  a.LastActivityDate,
  a.Score,
  a.ViewCount,
  a.Views,
  a.Location,
  a.Reputation,
  a.UpVotes,
  a.DownVotes,
  a.Body,
  a.Tags,
  a.CommentCountTotal,
  a.ChildAnswerCount,
  a.FavoriteCount,
  a.ProfileImageUrl,
  a.MetaKey,
  a.AvgScoreSimilarTags
FROM Aggregated a
ORDER BY a.LastActivityDate DESC
LIMIT 100;