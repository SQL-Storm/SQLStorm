-- {"query": "7486.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1798} 
WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
    LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as moving_avg_score
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
UserStats AS (
  SELECT 
    u.Id as UserId,
    u.Reputation,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) as PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
    MAX(p.CreationDate) as LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagPopularity AS (
  SELECT 
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank,
    PERCENT_RANK() OVER (ORDER BY t.Count) as popularity_percentile
  FROM Tags t
  WHERE t.Count > 0
),
RecentActivity AS (
  SELECT 
    ph.PostId,
    ph.UserId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.Comment,
    ph.Text,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as recent_action,
    LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as prev_action_date
  FROM PostHistory ph
  WHERE ph.CreationDate >= DATEADD(DAY, -30, GETDATE())
)
SELECT 
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.PostCount,
  us.QuestionCount,
  us.AnswerCount,
  CASE 
    WHEN us.PostCount > 0 THEN us.QuestionCount * 100.0 / us.PostCount 
    ELSE 0 
  END as QuestionPercentage,
  ps.Id as PostId,
  ps.Title,
  ps.Score,
  ps.ViewCount,
  ps.CreationDate,
  ps.LastActivityDate,
  ps.Tags,
  ps.AnswerCount as PostAnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  CASE 
    WHEN ps.Score > 0 AND ps.Score > ps.prev_score THEN 'Increasing'
    WHEN ps.Score < 0 AND ps.Score < ps.prev_score THEN 'Decreasing'
    ELSE 'Stable'
  END as ScoreTrend,
  ps.moving_avg_score,
  COALESCE(tp.TagName, 'No Tags') as MostPopularTag,
  CASE 
    WHEN ps.CreationDate >= DATEADD(DAY, -7, GETDATE()) THEN 'Recent'
    WHEN ps.CreationDate >= DATEADD(DAY, -30, GETDATE()) THEN 'Last Month'
    ELSE 'Older'
  END as PostAgeCategory,
  CASE 
    WHEN ps.Score > 100 THEN 'Highly Voted'
    WHEN ps.Score > 50 THEN 'Well Voted'
    WHEN ps.Score > 0 THEN 'Moderately Voted'
    WHEN ps.Score < 0 THEN 'Low Voted'
    ELSE 'No Votes'
  END as VotingCategory,
  DATEDIFF(DAY, ps.CreationDate, ps.LastActivityDate) as DaysSinceLastActivity,
  COUNT(DISTINCT r.PostId) as RecentActions,
  STRING_AGG(
    CASE 
      WHEN ra.PostHistoryTypeId IN (1, 2, 3) THEN 'Initial Creation'
      WHEN ra.PostHistoryTypeId IN (4, 5, 6) THEN 'Edit'
      WHEN ra.PostHistoryTypeId IN (10, 11) THEN 'Closure Status'
      ELSE 'Other'
    END, 
    ', '
  ) WITHIN GROUP (ORDER BY ra.CreationDate) as ActionTypes,
  COALESCE((
    SELECT TOP 1 bt.Name
    FROM Badges bt
    WHERE bt.UserId = us.UserId
    AND bt.Date >= DATEADD(DAY, -30, GETDATE())
    ORDER BY bt.Date DESC
  ), 'No Recent Badges') as RecentBadge,
  COALESCE((
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = ps.Id
    AND v.VoteTypeId IN (2, 3)
    AND v.CreationDate >= DATEADD(DAY, -30, GETDATE())
  ), 0) as RecentVotes,
  CASE 
    WHEN ps.OwnerUserId IS NOT NULL THEN 
      CASE 
        WHEN EXISTS (
          SELECT 1 
          FROM Posts p2 
          WHERE p2.ParentId = ps.Id 
          AND p2.PostTypeId = 2
          AND p2.Score > 0
        ) THEN 'Has Upvoted Answers'
        WHEN EXISTS (
          SELECT 1 
          FROM Posts p3 
          WHERE p3.ParentId = ps.Id 
          AND p3.PostTypeId = 2
        ) THEN 'Has Answers'
        ELSE 'No Answers'
      END
    ELSE 'Community Post'
  END as AnswerStatus,
  CASE 
    WHEN ps.CommentCount > 0 THEN 
      (SELECT STRING_AGG(c.Text, '; ') 
       FROM Comments c 
       WHERE c.PostId = ps.Id
       AND c.CreationDate >= DATEADD(DAY, -7, GETDATE())
       ORDER BY c.CreationDate)
    ELSE NULL
  END as RecentComments
FROM UserStats us
INNER JOIN RankedPosts ps ON us.UserId = ps.OwnerUserId AND ps.rn = 1
LEFT JOIN TagPopularity tp ON tp.popularity_rank = 1
LEFT JOIN RecentActivity r ON ps.Id = r.PostId 
LEFT JOIN RecentActivity ra ON ps.Id = ra.PostId
WHERE us.Reputation > 1000
  AND ps.CreationDate >= DATEADD(YEAR, -2, GETDATE())
  AND (ps.ViewCount >= 100 OR ps.Score >= 10 OR ps.AnswerCount >= 2)
  AND (
    ps.Title LIKE '%SQL%' 
    OR ps.Title LIKE '%query%'
    OR ps.Tags LIKE '%sql%'
    OR ps.Tags LIKE '%query%'
  )
  AND (ps.CommentCount > 0 OR ps.FavoriteCount > 0)
  AND NOT EXISTS (
    SELECT 1 
    FROM Posts p4 
    WHERE p4.ParentId = ps.Id 
    AND p4.PostTypeId = 2
    AND p4.Score < 0
    AND p4.CreationDate >= DATEADD(DAY, -30, GETDATE())
  )
GROUP BY 
  us.UserId, 
  us.DisplayName, 
  us.Reputation,
  us.PostCount,
  us.QuestionCount,
  us.AnswerCount,
  ps.Id,
  ps.Title,
  ps.Score,
  ps.ViewCount,
  ps.CreationDate,
  ps.LastActivityDate,
  ps.Tags,
  ps.AnswerCount,
  ps.CommentCount,
  ps.FavoriteCount,
  ps.prev_score,
  ps.moving_avg_score,
  tp.TagName
HAVING 
  COUNT(DISTINCT r.PostId) > 0
  AND COUNT(DISTINCT ps.Id) > 0
  AND (
    SUM(CASE WHEN ps.PostTypeId = 1 THEN ps.Score ELSE 0 END) > 50
    OR SUM(CASE WHEN ps.PostTypeId = 2 THEN ps.Score ELSE 0 END) > 100
  )
ORDER BY 
  us.Reputation DESC,
  ps.Score DESC,
  ps.LastActivityDate DESC
OPTION (MAXDOP 1)