-- {"query": "7993.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2878} 
WITH UserActivityStats AS (
  SELECT 
    u.Id as UserId,
    u.Reputation,
    u.DisplayName,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT b.Id) as Badges,
    MAX(p.CreationDate) as LastPostDate,
    AVG(p.Score) as AvgPostScore,
    STRING_AGG(DISTINCT u.Location, ', ') as Locations,
    CASE 
      WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Elite'
      WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Veteran'
      WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Active'
      ELSE 'Newbie' 
    END as UserCategory,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) as UserRank
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON u.Id = c.UserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE u.CreationDate >= '2010-01-01'
  GROUP BY u.Id, u.Reputation, u.DisplayName
),
QuestionStats AS (
  SELECT 
    p.Id as QuestionId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    u.DisplayName as AuthorName,
    u.Reputation as AuthorReputation,
    p.OwnerUserId,
    COALESCE(p.AnswerCount, 0) as AnswerCount,
    CASE 
      WHEN p.AnswerCount > 0 THEN 
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) /
        NULLIF((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id), 0)
      ELSE 0 
    END as UpvoteRatio,
    DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      ELSE 'Open'
    END as QuestionStatus,
    LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
    LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RecentRank
  FROM Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
AnswerStats AS (
  SELECT 
    p.Id as AnswerId,
    p.ParentId,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName as AnswererName,
    u.Reputation as AnswererReputation,
    CASE 
      WHEN p.ParentId IS NOT NULL THEN 
        (SELECT MAX(p2.Score) FROM Posts p2 WHERE p2.Id = p.ParentId)
      ELSE NULL 
    END as QuestionMaxScore,
    DATEDIFF(day, (SELECT MIN(p3.CreationDate) FROM Posts p3 WHERE p3.ParentId = p.ParentId), p.CreationDate) as DaysToAnswer,
    ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) as RankInQuestion,
    CASE 
      WHEN p.Score > 0 THEN 'Upvoted'
      WHEN p.Score < 0 THEN 'Downvoted'
      ELSE 'Neutral'
    END as ScoreCategory
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 2
),
PostActivity AS (
  SELECT 
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate,
    ph.Text,
    ph.Comment,
    ph.RevisionGUID,
    CASE 
      WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 'Initial'
      WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 'Edit'
      WHEN ph.PostHistoryTypeId IN (10, 11) THEN 'Status Change'
      WHEN ph.PostHistoryTypeId = 16 THEN 'Community Owned'
      ELSE 'Other'
    END as ActivityType,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as MostRecent,
    LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as PrevActivityDate
  FROM PostHistory ph
  WHERE ph.CreationDate >= '2020-01-01'
)
SELECT 
  'Performance Benchmark Report' as ReportName,
  COUNT(DISTINCT uas.UserId) as TotalUsers,
  COUNT(DISTINCT qs.QuestionId) as TotalQuestions,
  COUNT(DISTINCT asa.AnswerId) as TotalAnswers,
  COUNT(DISTINCT ps.PostId) as TotalPostActivities,
  AVG(uas.AvgPostScore) as AvgUserPostScore,
  MAX(uas.Reputation) as TopReputation,
  MIN(uas.LastPostDate) as EarliestUserPost,
  MAX(COALESCE(qs.CreationDate, asa.CreationDate, ps.CreationDate)) as LatestActivity,
  (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01') as RecentQuestions,
  (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.CreationDate >= '2020-01-01') as RecentAnswers,
  (SELECT COUNT(*) FROM Badges b WHERE b.Date >= '2020-01-01') as RecentBadges,
  (SELECT COUNT(*) FROM Comments c WHERE c.CreationDate >= '2020-01-01') as RecentComments,
  (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.CreationDate >= '2020-01-01') as ActiveEditors,
  (
    SELECT COUNT(DISTINCT p.Id) 
    FROM Posts p 
    INNER JOIN PostHistory ph ON p.Id = ph.PostId 
    WHERE ph.CreationDate >= '2020-01-01' 
    AND ph.PostHistoryTypeId IN (1, 2, 3)
  ) as EditedPosts,
  (
    CASE 
      WHEN COUNT(DISTINCT uas.UserId) > 0 THEN 
        CAST(SUM(uas.TotalPosts) AS FLOAT) / COUNT(DISTINCT uas.UserId)
      ELSE 0 
    END
  ) as AvgPostsPerUser,
  STRING_AGG(
    CASE 
      WHEN uas.UserCategory = 'Elite' THEN CONCAT(uas.DisplayName, ' (', uas.Reputation, ')')
      ELSE NULL 
    END, 
    '; '
  ) as EliteUsers,
  (
    SELECT COUNT(DISTINCT p.OwnerUserId) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND EXISTS (
      SELECT 1 FROM Posts p2 
      WHERE p2.ParentId = p.Id 
      AND p2.PostTypeId = 2 
      AND p2.Score > 0
    )
  ) as QuestionsWithGoodAnswers,
  (
    SELECT COUNT(*) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND EXISTS (
      SELECT 1 FROM Votes v 
      WHERE v.PostId = p.Id 
      AND v.VoteTypeId = 1
    )
  ) as QuestionsWithAcceptedAnswers,
  (
    SELECT COUNT(DISTINCT p.Id) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND p.AnswerCount > 10
  ) as HighAnsweredQuestions,
  (
    SELECT COUNT(DISTINCT p.OwnerUserId) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND p.CreationDate >= '2020-01-01'
  ) as ActiveQuestionAuthors,
  (
    SELECT (COUNT(DISTINCT ps.PostId) * 100.0) / NULLIF(COUNT(DISTINCT qs.QuestionId), 0)
    FROM PostActivity ps
    INNER JOIN Posts qs ON ps.PostId = qs.Id
    WHERE qs.PostTypeId = 1
  ) as PostActivityPercentage,
  (
    SELECT COUNT(*) 
    FROM PostHistory ph 
    WHERE ph.PostHistoryTypeId = 10 
    AND ph.Comment LIKE '%duplicate%'
  ) as DuplicateClosedQuestions,
  (
    SELECT COUNT(*) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND p.Score > 100
  ) as HighlyScoredQuestions,
  (
    SELECT COUNT(DISTINCT p.Id) 
    FROM Posts p 
    INNER JOIN Posts p2 ON p.Id = p2.ParentId 
    WHERE p.PostTypeId = 1 
    AND p2.Score < 0
  ) as QuestionsWithDownvotedAnswers,
  (
    SELECT COUNT(DISTINCT u.Id) 
    FROM Users u 
    WHERE u.Reputation > 10000 
    AND EXISTS (
      SELECT 1 FROM Posts p 
      WHERE p.OwnerUserId = u.Id 
      AND p.PostTypeId = 1
    )
  ) as HighRepQuestionAuthors,
  (
    SELECT COUNT(*) 
    FROM Posts p 
    WHERE p.PostTypeId = 2 
    AND p.OwnerUserId IS NOT NULL
    AND p.OwnerUserId > 0
  ) as AnsweredAnswers,
  (
    SELECT COUNT(*) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND COALESCE(p.AnswerCount, 0) = 0
  ) as UnansweredQuestions,
  (
    SELECT COUNT(DISTINCT u.Id) 
    FROM Users u 
    WHERE u.Id IN (
      SELECT DISTINCT ph.UserId 
      FROM PostHistory ph 
      WHERE ph.CreationDate >= '2020-01-01'
    )
    AND EXISTS (
      SELECT 1 FROM Posts p 
      WHERE p.OwnerUserId = u.Id 
      AND p.PostTypeId = 1
    )
  ) as ActiveAuthors,
  (
    SELECT COUNT(DISTINCT p.Id) 
    FROM Posts p 
    INNER JOIN Tags t ON p.Tags LIKE '%' + t.TagName + '%'
    WHERE p.PostTypeId = 1
  ) as TaggedQuestions,
  (
    SELECT COUNT(DISTINCT ph.PostId) 
    FROM PostHistory ph 
    WHERE ph.PostHistoryTypeId IN (1, 2, 3) 
    AND ph.CreationDate >= '2020-01-01'
  ) as InitialContentPosts,
  (
    SELECT COUNT(DISTINCT p.Id) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND p.OwnerUserId IN (1, 2, 3)
  ) as CommunityQuestions,
  (
    SELECT MAX(p.Score) 
    FROM Posts p 
    WHERE p.PostTypeId = 1
  ) as MaxQuestionScore,
  (
    SELECT AVG(p.Score) 
    FROM Posts p 
    WHERE p.PostTypeId = 2
  ) as AvgAnswerScore,
  (
    SELECT COUNT(*) 
    FROM PostHistory ph 
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
  ) as StatusChangeActivities,
  (
    SELECT COUNT(*) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND EXISTS (
      SELECT 1 FROM Votes v 
      WHERE v.PostId = p.Id 
      AND v.VoteTypeId = 5
    )
  ) as FavoritedQuestions,
  (
    SELECT COUNT(DISTINCT p.OwnerUserId) 
    FROM Posts p 
    WHERE p.PostTypeId = 1 
    AND p.Score > 0 
    AND p.AnswerCount > 0
  ) as PositiveScoreQuestions,
  (
    SELECT COUNT(DISTINCT p.Id) 
    FROM Posts p 
    WHERE p.PostTypeId = 2 
    AND p.Score > 0 
    AND EXISTS (
      SELECT 1 FROM Posts p2 
      WHERE p2.Id = p.ParentId 
      AND p2.Score > 10
    )
  ) as GoodAnswersToHighScoreQuestions
FROM UserActivityStats uas
FULL OUTER JOIN QuestionStats qs ON 1=1
FULL OUTER JOIN AnswerStats asa ON 1=1
FULL OUTER JOIN PostActivity ps ON 1=1
WHERE uas.UserId IS NOT NULL OR qs.QuestionId IS NOT NULL OR asa.AnswerId IS NOT NULL OR ps.PostId IS NOT NULL
HAVING COUNT(DISTINCT uas.UserId) > 0 OR COUNT(DISTINCT qs.QuestionId) > 0 OR COUNT(DISTINCT asa.AnswerId) > 0 OR COUNT(DISTINCT ps.PostId) > 0;