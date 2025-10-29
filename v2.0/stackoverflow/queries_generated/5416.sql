-- {"query": "5416.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 846} 
WITH top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS rn
  FROM Users u
),
recent_moderators AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.AccountId,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges
  FROM Users u
  WHERE EXISTS (
    SELECT 1
    FROM Votes v
    JOIN PostHistory ph ON ph.PostId = v.PostId
    WHERE v.UserId = u.Id
      AND v.VoteTypeId IN (14, 15) -- Moderator related votes
  )
),
hot_tag_wiki AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
    AND t.Count > 1000
),
complex_post_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    ARRAY_AGG(DISTINCT lt.Name) AS LinkTypesUsed
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY
    p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate,
    p.Score, p.ViewCount, p.CommentCount, p.AnswerCount
),
activity_score AS (
  SELECT
    a.PostId,
    a.Title,
    a.PostTypeId,
    a.OwnerUserId,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.CommentCount,
    a.AnswerCount,
    (a.Score * 2 + a.ViewCount / 10 + a.CommentCount * 3 + a.AnswerCount * 5) AS ScoreMetric,
    ROW_NUMBER() OVER (ORDER BY (a.Score * 2 + a.ViewCount / 10 + a.CommentCount * 3 + a.AnswerCount * 5) DESC) AS rn
  FROM complex_post_activity a
)
SELECT
  up.rn AS top_user_rank,
  up.Id AS UserId,
  up.DisplayName AS UserDisplayName,
  up.Reputation,
  up.AccountId,
  rm.Id AS ModeratorUserId,
  rm.DisplayName AS ModeratorDisplayName,
  rm.GoldBadges,
  htw.TagName AS HotTag,
  htw.Count AS TagCount,
  ac.PostId,
  ac.Title AS PostTitle,
  ac.PostTypeId,
  ac.OwnerUserId,
  ac.CreationDate AS PostCreationDate,
  ac.LastActivityDate AS PostLastActivityDate,
  ac.Score,
  ac.ViewCount,
  ac.CommentCount,
  ac.AnswerCount,
  ac.ScoreMetric
FROM top_users up
LEFT JOIN recent_moderators rm ON rm.AccountId = up.AccountId OR rm.Id = up.Id
LEFT JOIN hot_tag_wiki htw ON 1=1
LEFT JOIN activity_score ac ON ac.PostId = (SELECT Id FROM Posts WHERE OwnerUserId = up.Id ORDER BY LastActivityDate DESC LIMIT 1)
WHERE up.rn <= 100
ORDER BY up.Reputation DESC, rm.GoldBadges DESC, ac.ScoreMetric DESC
LIMIT 100;