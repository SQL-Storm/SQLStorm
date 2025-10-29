-- {"query": "5959.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1022} 
WITH
  RecentActivePosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.LastActivityDate,
      p.ViewCount,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ParentId,
      p.AcceptedAnswerId
    FROM Posts p
    WHERE p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '30 days')
  ),
  UserRank AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      ROW_NUMBER() OVER (
        ORDER BY u.Reputation DESC,
                 u.UpVotes DESC,
                 u.LastAccessDate DESC
      ) AS rk
    FROM Users u
  ),
  TagInvolvement AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS PostCount,
      AVG(p.Score) AS AvgScore,
      MAX(p.LastActivityDate) AS LastActive
    FROM Posts p
    CROSS APPLY (
      SELECT TRIM(value) AS TagName
      FROM STRING_SPLIT(p.Tags, '<>')
    ) AS t
    GROUP BY t.TagName
  ),
  Edits AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ph.UserId,
      ph.UserDisplayName,
      ph.Text,
      ph.Comment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,14,15,16,17,18,19,20,24,33,34,36,37,38)
  ),
  Activity as (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.LastActivityDate,
      p.ViewCount,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      CASE
        WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
        ELSE COALESCE(uu.DisplayName, p.OwnerDisplayName)
      END AS EffectiveOwner,
      COALESCE(uu.Reputation, 0) AS OwnerReputation
    FROM RecentActivePosts p
    LEFT JOIN Users uu ON p.OwnerUserId = uu.Id
  ),
  ComplexQuery AS (
    SELECT
      a.PostId,
      a.PostTypeId,
      a.OwnerUserId,
      a.EffectiveOwner,
      a.OwnerReputation,
      a.LastActivityDate,
      a.ViewCount,
      a.Score,
      a.AnswerCount,
      a.CommentCount,
      a.FavoriteCount,
      a.Title,
      a.Tags,
      -- Correlated subquery: count of related posts via PostLinks (duplicates/links)
      (SELECT COUNT(*) FROM PostLinks pl
       WHERE pl.PostId = a.PostId) AS LinkCount,
      -- Window function: rank of post by LastActivityDate within its type
      ROW_NUMBER() OVER (PARTITION BY a.PostTypeId ORDER BY a.LastActivityDate DESC) AS TypeRank,
      -- NULL-safe calculation: score per view ratio
      CASE WHEN a.ViewCount = 0 THEN NULL ELSE CAST(a.Score AS DECIMAL(10,2)) / a.ViewCount END AS ScorePerView,
      -- String expression: length of title
      LENGTH(a.Title) AS TitleLength
    FROM Activity a
    LEFT JOIN Tags t ON t.TagName = ANY(string_to_array(substring(a.Tags from 2 for length(a.Tags)-2), '><'))
  )
SELECT
  c.PostId,
  c.PostTypeId,
  pt.Name AS PostTypeName,
  c.OwnerUserId,
  c.EffectiveOwner,
  c.OwnerReputation,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.Title,
  c.Tags,
  c.LinkCount,
  c.TypeRank,
  c.ScorePerView,
  c.TitleLength,
  ru.rk AS UserRank,
  ru.DisplayName AS UserDisplayName,
  ru.Reputation AS UserReputation,
  bh.Date AS BadgeDate,
  bh.Name AS BadgeName
FROM ComplexQuery c
LEFT JOIN PostTypes pt ON c.PostTypeId = pt.Id
LEFT JOIN UserRank ru ON c.OwnerUserId = ru.UserId
LEFT JOIN Badges bh ON bh.UserId = c.OwnerUserId
WHERE
  (c.Score > 0 OR c.ViewCount > 100)
  AND (c.LastActivityDate IS NOT NULL)
  AND (c.TypeRank <= 50)
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 200;