-- {"query": "51022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1534} 

WITH ActiveUsers AS (
  SELECT u.Id, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
  FROM Users u
  WHERE u.Reputation > 1000
    AND u.CreationDate >= NOW() - INTERVAL '5 years'
    AND u.UpVotes > u.DownVotes * 2
),
TopQuestions AS (
  SELECT p.Id, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Title,
         p.OwnerUserId, au.Reputation as OwnerReputation
  FROM Posts p
  INNER JOIN ActiveUsers au ON p.OwnerUserId = au.Id
  WHERE p.PostTypeId = 1
    AND p.Score >= 50
    AND p.AnswerCount >= 3
    AND p.ViewCount > 10000
    AND p.CreationDate >= NOW() - INTERVAL '2 years'
  ORDER BY p.Score * 1.0 / (EXTRACT(EPOCH FROM (NOW() - p.CreationDate))/86400 + 1) DESC
  LIMIT 1000
),
UserEngagement AS (
  SELECT 
    au.Id as UserId,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.PostId END) as EditsMade,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11) THEN ph.PostId END) as CloseReopenActions,
    AVG(EXTRACT(EPOCH FROM (ph.CreationDate - au.CreationDate))/86400) as DaysToFirstActivity,
    SUM(CASE WHEN ph.PostHistoryTypeId = 24 THEN 1 ELSE 0 END) as SuggestedEditsApplied
  FROM ActiveUsers au
  INNER JOIN PostHistory ph ON ph.UserId = au.Id
  WHERE ph.CreationDate >= au.CreationDate + INTERVAL '1 day'
    AND ph.PostHistoryTypeId IN (4,5,6,10,11,24)
  GROUP BY au.Id
  HAVING COUNT(DISTINCT ph.PostId) > 5
),
QuestionTags AS (
  SELECT 
    tq.post_id,
    string_agg(t.TagName, ',' ORDER BY t.Count DESC) as TagNames,
    COUNT(DISTINCT t.Id) as TagCount,
    MAX(t.Count) as PopularTagCount
  FROM (
    SELECT 
      p.Id as post_id,
      unnest(string_to_array(
        substring(p.Tags, 2, length(p.Tags)-2), 
        '><'
      )) as tag_name
    FROM TopQuestions tq
    INNER JOIN Posts p ON p.Id = tq.Id
    WHERE p.Tags IS NOT NULL AND length(p.Tags) > 2
  ) tq
  INNER JOIN Tags t ON t.TagName = tq.tag_name
  GROUP BY tq.post_id
),
VotePatterns AS (
  SELECT 
    v.PostId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as Upvotes,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as Downvotes,
    COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as Favorites,
    COUNT(DISTINCT v.UserId) as UniqueVoters,
    AVG(v.BountyAmount) as AvgBounty
  FROM Votes v
  WHERE v.PostId IN (SELECT Id FROM TopQuestions)
    AND v.VoteTypeId IN (2,3,5,8)
  GROUP BY v.PostId
  HAVING COUNT(*) > 10
),
NetworkAnalysis AS (
  SELECT 
    pl.PostId,
    COUNT(DISTINCT pl.RelatedPostId) as OutboundLinks,
    COUNT(DISTINCT pl2.PostId) as InboundLinks,
    AVG(CASE WHEN pl.LinkTypeId = 3 THEN 1.0 ELSE 0 END) as DuplicateRatio
  FROM PostLinks pl
  INNER JOIN PostLinks pl2 ON pl.RelatedPostId = pl2.PostId
  WHERE pl.PostId IN (SELECT Id FROM TopQuestions)
    AND pl2.RelatedPostId IN (SELECT Id FROM TopQuestions)
  GROUP BY pl.PostId
)
SELECT 
  tq.Id as QuestionId,
  tq.Title,
  tq.Score as QuestionScore,
  tq.ViewCount,
  tq.AnswerCount,
  tq.FavoriteCount,
  tq.OwnerReputation,
  COALESCE(vp.Upvotes, 0) as TotalUpvotes,
  COALESCE(vp.Downvotes, 0) as TotalDownvotes,
  COALESCE(vp.Favorites, 0) as TotalFavorites,
  COALESCE(vp.UniqueVoters, 0) as UniqueVoters,
  COALESCE(na.OutboundLinks, 0) as OutboundLinks,
  COALESCE(na.InboundLinks, 0) as InboundLinks,
  COALESCE(qt.TagNames, '') as Tags,
  COALESCE(qt.TagCount, 0) as TagCount,
  COALESCE(qt.PopularTagCount, 0) as PopularTagWeight,
  ue.EditsMade,
  ue.CloseReopenActions,
  ue.SuggestedEditsApplied,
  ROUND(
    (tq.Score * 0.4 + 
     tq.AnswerCount * 10 * 0.2 + 
     tq.ViewCount / 1000 * 0.15 + 
     COALESCE(vp.Upvotes, 0) * 0.15 + 
     COALESCE(na.InboundLinks, 0) * 5 * 0.1) / 
    (EXTRACT(EPOCH FROM (NOW() - tq.CreationDate))/86400 + 1), 2
  ) as QualityScore,
  CASE 
    WHEN tq.AnswerCount >= 5 AND COALESCE(vp.Upvotes, 0) > 50 THEN 'Highly Engaged'
    WHEN tq.ViewCount > 50000 AND COALESCE(na.OutboundLinks, 0) > 3 THEN 'Viral Network'
    WHEN ue.EditsMade > 10 AND ue.SuggestedEditsApplied > 5 THEN 'Active Editor'
    ELSE 'Standard'
  END as EngagementCategory,
  RANK() OVER (
    ORDER BY 
      (tq.Score * 0.4 + 
       tq.AnswerCount * 10 * 0.2 + 
       tq.ViewCount / 1000 * 0.15 + 
       COALESCE(vp.Upvotes, 0) * 0.15) DESC
  ) as OverallRank
FROM TopQuestions tq
LEFT JOIN VotePatterns vp ON tq.Id = vp.PostId
LEFT JOIN QuestionTags qt ON tq.Id = qt.post_id
LEFT JOIN NetworkAnalysis na ON tq.Id = na.PostId
LEFT JOIN UserEngagement ue ON tq.OwnerUserId = ue.UserId
LEFT JOIN Badges b ON tq.OwnerUserId = b.UserId 
  AND b.Name IN ('Famous Question', 'Notable Question', 'Popular Question')
WHERE (b.Id IS NOT NULL OR tq.Score > 20)
ORDER BY QualityScore DESC, OverallRank ASC
LIMIT 100;
