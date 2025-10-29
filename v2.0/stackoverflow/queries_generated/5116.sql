-- {"query": "5116.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 914} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditDate,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    -- window function: rank posts per day by score and viewcount
    ROW_NUMBER() OVER (
      PARTITION BY DATE(p.CreationDate)
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS DayRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
RecentActivity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.DayRank,
    -- correlated subquery: number of comments on post up to last activity date
    (
      SELECT COUNT(*) FROM Comments c
      WHERE c.PostId = rp.PostId
        AND c.CreationDate <= rp.LastActivityDate
    ) AS CommentCountTillLastActivity,
    -- correlated subquery: total votes (up + down) up to last activity date
    (
      SELECT COUNT(*) * 0 + SUM(v.BountyAmount)
      FROM Votes v
      WHERE v.PostId = rp.PostId
        AND v.CreationDate <= rp.LastActivityDate
    ) AS AggregateVotesUntilLastActivity
  FROM RankedPosts rp
  WHERE rp.DayRank <= 5 -- top 5 posts per day by our ranking
),
CrossLinked AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.OwnerDisplayName,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.DayRank,
    COALESCE(br.Name, 'NoBadges') AS BadgeName
  FROM RecentActivity ra
  LEFT JOIN Badges b ON ra.OwnerUserId = b.UserId
  LEFT JOIN (
    SELECT DISTINCT UserId, MAX(Date) AS MaxDate, Name
    FROM Badges
    GROUP BY UserId, Name
  ) br ON ra.OwnerUserId = br.UserId
  -- a little complexity: compute if post has a linked post that is a duplicate
  LEFT JOIN PostLinks pl ON ra.PostId = pl.PostId AND pl.LinkTypeId = 3
  LEFT JOIN Posts dup ON pl.RelatedPostId = dup.Id
),
FinalAgg AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.CreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.DayRank,
    c.BadgeName,
    dup.Title AS DuplicateOfTitle,
    dup.Id AS DuplicateOfPostId,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT STRING_AGG(t.TagName, ',') FROM Tags t
     JOIN Posts p ON t.Id = p.Tags::int)
      AS TagsSnapshot
  FROM CrossLinked c
  LEFT JOIN Posts dup ON c.PostId = dup.Id
)
SELECT
  PostId,
  Title,
  OwnerUserId,
  OwnerDisplayName,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  DayRank,
  BadgeName,
  DuplicateOfPostId,
  DuplicateOfTitle,
  UpVotes,
  DownVotes,
  TagsSnapshot
FROM FinalAgg
ORDER BY LastActivityDate DESC, Score DESC
LIMIT 100;