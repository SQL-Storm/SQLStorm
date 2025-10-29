-- {"query": "7819.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1941} 
WITH UserActivityStats AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesGiven,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesGiven,
    MAX(p.CreationDate) AS LastPostDate,
    MAX(c.CreationDate) AS LastCommentDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS ReputationRank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRankDense
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c ON u.Id = c.UserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN Votes v ON u.Id = v.UserId
  WHERE u.Id > 0
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
  SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CreationDate,
    p.PostTypeId,
    p.ParentId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
    COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPostsPerType
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) 
    AND p.Score IS NOT NULL 
    AND p.ViewCount >= 1000
),
TagAnalysis AS (
  SELECT 
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    CASE 
      WHEN t.Count > 1000 THEN 'High'
      WHEN t.Count > 100 THEN 'Medium'
      ELSE 'Low'
    END AS TagPopularity,
    (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS PostsWithTag,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS AvgScoreForTag
  FROM Tags t
  WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
UserPerformance AS (
  SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    uas.BadgeCount,
    uas.UpvotesGiven,
    uas.DownvotesGiven,
    uas.ReputationRank,
    uas.ReputationRankDense,
    CASE 
      WHEN uas.QuestionCount > 0 AND uas.AnswerCount > 0 THEN 
        ROUND((uas.AnswerCount::FLOAT / uas.QuestionCount::FLOAT) * 100, 2)
      ELSE 0
    END AS AnswerToQuestionRatio,
    CASE 
      WHEN uas.BadgeCount > 0 THEN 
        uas.BadgeCount / uas.Reputation::FLOAT
      ELSE 0
    END AS BadgesPerReputation,
    CASE 
      WHEN uas.UpvotesGiven > 0 THEN 
        ROUND((uas.UpvotesGiven::FLOAT / (uas.UpvotesGiven + uas.DownvotesGiven)::FLOAT) * 100, 2)
      ELSE 0
    END AS UpvoteRatio
  FROM UserActivityStats uas
  WHERE uas.Reputation > 0 AND uas.TotalPosts > 0
),
ComplexQueryResult AS (
  SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.TotalPosts,
    up.QuestionCount,
    up.AnswerCount,
    up.CommentCount,
    up.BadgeCount,
    up.UpvotesGiven,
    up.DownvotesGiven,
    up.ReputationRank,
    up.ReputationRankDense,
    up.AnswerToQuestionRatio,
    up.BadgesPerReputation,
    up.UpvoteRatio,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.CreationDate,
    tp.PostTypeId,
    tp.AnswerCount AS PostAnswerCount,
    tp.CommentCount AS PostCommentCount,
    tp.FavoriteCount,
    ta.TagName,
    ta.TagCount,
    ta.TagPopularity,
    ta.PostsWithTag,
    ta.AvgScoreForTag,
    CASE 
      WHEN tp.PostTypeId = 1 AND tp.AnswerCount > 0 AND tp.ViewCount > 0 THEN 
        ROUND((tp.AnswerCount::FLOAT / tp.ViewCount::FLOAT) * 100, 2)
      ELSE 0
    END AS AnswerDensity,
    CASE 
      WHEN tp.PostTypeId = 2 AND tp.Score > 0 THEN 
        ROUND((tp.Score::FLOAT / (tp.Score + 100)) * 100, 2)
      ELSE 0
    END AS ScoreEffectiveness,
    CASE 
      WHEN tp.Tags IS NOT NULL AND tp.Tags != '' THEN 
        array_length(string_to_array(tp.Tags, '><'), 1)
      ELSE 0
    END AS TagCountInPost,
    CASE 
      WHEN tp.PostTypeId = 1 AND tp.FavoriteCount IS NULL THEN 0
      ELSE tp.FavoriteCount
    END AS EffectiveFavorites,
    CASE 
      WHEN uas.Views > 0 AND uas.TotalPosts > 0 THEN 
        ROUND((uas.Views::FLOAT / uas.TotalPosts::FLOAT), 2)
      ELSE 0
    END AS AvgViewsPerPost,
    CASE 
      WHEN uas.UpVotes > 0 AND uas.DownVotes > 0 THEN 
        ROUND((uas.UpVotes::FLOAT / uas.DownVotes::FLOAT), 2)
      ELSE 0
    END AS UpVoteToDownVoteRatio,
    COALESCE(tp.Title, 'No Title') AS TitleOrPlaceholder,
    COALESCE(ta.TagName, 'No Tag') AS TagOrPlaceholder,
    CASE 
      WHEN up.Reputation > 10000 THEN 'Elite'
      WHEN up.Reputation > 5000 THEN 'Veteran'
      WHEN up.Reputation > 1000 THEN 'Regular'
      ELSE 'Newbie'
    END AS UserTier,
    CASE 
      WHEN tp.Score > 100 THEN 'High Impact'
      WHEN tp.Score > 20 THEN 'Moderate Impact'
      ELSE 'Low Impact'
    END AS PostImpact,
    CASE 
      WHEN tp.CommentCount > 50 THEN 'Highly Commented'
      WHEN tp.CommentCount > 10 THEN 'Moderately Commented'
      ELSE 'Low Comment Volume'
    END AS CommentVolume,
    DENSE_RANK() OVER (ORDER BY tp.Score DESC) AS PostScoreRank,
    RANK() OVER (ORDER BY tp.ViewCount DESC) AS PostViewRank
  FROM UserPerformance up
  LEFT JOIN UserActivityStats uas ON up.UserId = uas.UserId
  LEFT JOIN TopPosts tp ON tp.PostRank <= 5
  LEFT JOIN TagAnalysis ta ON ta.TagCount > 50
  WHERE up.Reputation > 5000 
    AND up.TotalPosts >= 10
    AND (tp.PostId IS NULL OR tp.PostId IS NOT NULL)
    AND (ta.TagName IS NULL OR ta.TagName IS NOT NULL)
)

SELECT * FROM ComplexQueryResult
WHERE 
  (ReputationRank BETWEEN 1 AND 50 OR ReputationRank IS NULL)
  AND 
  (
    (TotalPosts >= 100 AND QuestionCount >= 50) 
    OR 
    (AnswerCount >= 100 AND UpvotesGiven >= 1000)
  )
  OR 
  (
    PostImpact = 'High Impact' OR PostImpact IS NULL
  )
  AND 
  (
    (TagCount > 100 AND PostsWithTag > 1000) 
    OR 
    (AvgScoreForTag > 50 AND TagPopularity = 'High')
  )
  AND (TitleOrPlaceholder LIKE '%SQL%' OR TitleOrPlaceholder IS NULL)
  AND (TagOrPlaceholder LIKE '%query%' OR TagOrPlaceholder IS NULL)
ORDER BY 
  Reputation DESC, 
  TotalPosts DESC, 
  PostScoreRank ASC, 
  PostViewRank ASC
LIMIT 1000;