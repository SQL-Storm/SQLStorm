-- {"query": "1326.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1379} 
WITH RecentActivity AS (
  SELECT 
    p.Id, p.PostTypeId, p.ParentId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate,
    p.Tags,
    COALESCE(p.Title, CONCAT('Post #', p.Id)) AS DisplayTitle,
    u.DisplayName AS OwnerName,
    COUNT(c.Id) AS CommentCount,
    MAX(ph.CreationDate) AS LastEditDate,
    SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
    SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6) -- edits on title/body/tags
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY p.Id, p.PostTypeId, p.ParentId, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, 
           p.Tags, p.Title, u.DisplayName
), RankedPosts AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY Score DESC, ViewCount DESC, CreationDate DESC) AS Rnk,
    COUNT(*) OVER (PARTITION BY PostTypeId) AS TotalPosts
  FROM RecentActivity
), AcceptedAnswersDetail AS (
  SELECT 
    a.Id AS AnswerId, a.ParentId AS QuestionId, a.Score AS AnswerScore, u.DisplayName AS AnswerOwner,
    COALESCE(a.OwnerUserId,-1) AS OwnerId, a.CreationDate AS AnswerCreated,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank
  FROM Posts a
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  WHERE a.PostTypeId = 2
), QuestionVotesPct AS (
  SELECT 
    q.Id AS QuestionId,
    COUNT(v.Id) FILTER(WHERE vt.Name = 'UpMod')::float / NULLIF(COUNT(v.Id), 0) AS UpVotePercent,
    COUNT(v.Id) FILTER(WHERE vt.Name = 'DownMod')::float / NULLIF(COUNT(v.Id), 0) AS DownVotePercent
  FROM Posts q
  LEFT JOIN Votes v ON v.PostId = q.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id
), DuplicateLinkedPosts AS (
  SELECT DISTINCT pl.PostId AS QuestionId, COUNT(pl.Id) OVER (PARTITION BY pl.PostId) AS DupCount
  FROM PostLinks pl
  INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id AND lt.Name = 'Duplicate'
), CollatedTags AS (
  SELECT 
    p.Id AS PostId,
    STRING_AGG(t.TagName, ',' ORDER BY t.TagName) AS SortedTags
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT TRIM(tag) AS TagName
    FROM unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) AS tag
   ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  GROUP BY p.Id
), QuestionBadgesCount AS (
  SELECT
    u.Id AS UserId,
    COUNT(b.Id) FILTER(WHERE b.Class=1) AS GoldBadges,
    COUNT(b.Id) FILTER(WHERE b.Class=2) AS SilverBadges,
    COUNT(b.Id) FILTER(WHERE b.Class=3) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
)
SELECT 
  q.Id AS QuestionId,
  q.DisplayTitle,
  q.CreationDate,
  q.Score,
  q.ViewCount,
  q.CommentCount,
  q.UpVotes,
  q.DownVotes,
  COALESCE(d.DupCount, 0) AS DuplicateLinks,
  qbt.UpVotePercent,
  qbt.DownVotePercent,
  COALESCE(cb.GoldBadges,0) AS AuthorGold,
  COALESCE(cb.SilverBadges,0) AS AuthorSilver,
  COALESCE(cb.BronzeBadges,0) AS AuthorBronze,
  at.AnswerId AS AcceptedAnswerId,
  at.AnswerScore,
  at.AnswerOwner,
  subtop.AnswerId AS TopAnswerId,
  subtop.AnswerScore AS TopAnswerScore,
  subtop.AnswerOwner AS TopAnswerOwner,
  ct.SortedTags,
  ROW_NUMBER() OVER (ORDER BY q.CreationDate DESC) AS RecentRank,
  CONCAT('Q:', q.Id, '_', COALESCE(NULLIF(REPLACE(REPLACE(REPLACE(q.DisplayTitle, '''', ''), ',', ''), ' ', '_'), ''), 'untitled')) AS UniqueSlug
FROM RankedPosts q
LEFT JOIN AcceptedAnswersDetail at ON at.QuestionId = q.Id AND at.AnswerId = q.AcceptedAnswerId
LEFT JOIN (
  SELECT DISTINCT ON (a.ParentId) a.AnswerId, a.ParentId, a.AnswerScore, a.AnswerOwner
  FROM AcceptedAnswersDetail a
  WHERE a.AnswerId IS NOT NULL
  ORDER BY a.ParentId, a.AnswerScore DESC, a.AnswerCreated
) subtop ON subtop.ParentId = q.Id AND subtop.AnswerId <> q.AcceptedAnswerId
LEFT JOIN DuplicateLinkedPosts d ON d.QuestionId = q.Id
LEFT JOIN QuestionVotesPct qbt ON qbt.QuestionId = q.Id
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN QuestionBadgesCount cb ON cb.UserId = u.Id
LEFT JOIN CollatedTags ct ON ct.PostId = q.Id
WHERE q.PostTypeId = 1
  AND q.Rnk <= 100
  AND (q.Score > 5 OR (q.ViewCount > 1000 AND q.UpVotes > q.DownVotes))
ORDER BY q.Score DESC, q.ViewCount DESC, q.CreationDate DESC;