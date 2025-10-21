-- {"query": "21048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1403} 

WITH ActiveUsers AS (
    SELECT u.Id AS UserId, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '1 year'
),
RecentQuestions AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
           p.CreationDate, p.Title,
           COALESCE(p.CommentCount, 0) AS CommentCount,
           CASE 
               WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
               WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
               ELSE 'Open'
           END AS PostStatus
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
      AND p.DeletionDate IS NULL
),
TopAnswers AS (
    SELECT pa.ParentId, pa.Id AS AnswerId, pa.Score AS AnswerScore,
           ROW_NUMBER() OVER (PARTITION BY pa.ParentId ORDER BY pa.Score DESC, pa.CreationDate ASC) AS AnswerRank
    FROM Posts pa
    INNER JOIN RecentQuestions rq ON pa.ParentId = rq.PostId
    WHERE pa.PostTypeId = 2
),
EngagementMetrics AS (
    SELECT rq.PostId, rq.OwnerUserId,
           rq.Score + COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0) AS NetScore,
           rq.ViewCount * 1.0 / NULLIF(rq.AnswerCount, 0) AS ViewsPerAnswer,
           GREATEST(rq.AnswerCount, 1) AS EffectiveAnswerCount,
           SUBSTRING(rq.Tags FROM 2 FOR LENGTH(rq.Tags) - 2) AS TagList,
           -- Extract first tag for categorization
           CASE 
               WHEN rq.Tags LIKE '<java>%' THEN 'Java'
               WHEN rq.Tags LIKE '<python>%' THEN 'Python'
               WHEN rq.Tags LIKE '<javascript>%' THEN 'JavaScript'
               WHEN rq.Tags LIKE '<sql>%' THEN 'SQL'
               ELSE 'Other'
           END AS PrimaryTagCategory,
           -- Complex string manipulation for title analysis
           LENGTH(rq.Title) + (SELECT COUNT(*) FROM UNNEST(string_to_array(rq.Title, ' ')) AS word WHERE LENGTH(word) > 6) AS TitleComplexity
    FROM RecentQuestions rq
    LEFT JOIN (
        SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ) v ON rq.PostId = v.PostId
),
VotePatterns AS (
    SELECT au.UserId,
           COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS TotalUpvotes,
           COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS TotalDownvotes,
           COUNT(CASE WHEN vt.Name = 'UpMod' AND vo.CreationDate >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) AS RecentUpvotes,
           ROUND(
               100.0 * COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END)::float / 
               NULLIF(COUNT(CASE WHEN vt.Name IN ('UpMod', 'DownMod') THEN 1 END), 0), 2
           ) AS UpvoteRatio
    FROM ActiveUsers au
    INNER JOIN Votes vo ON au.UserId = vo.UserId
    INNER JOIN VoteTypes vt ON vo.VoteTypeId = vt.Id
    WHERE vo.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY au.UserId
    HAVING COUNT(vo.Id) > 10
)
SELECT 
    em.PostId,
    em.OwnerUserId,
    au.RepRank AS UserReputationRank,
    em.PrimaryTagCategory,
    em.NetScore,
    em.ViewsPerAnswer,
    ta.AnswerScore AS BestAnswerScore,
    vp.UpvoteRatio AS UserUpvoteRatio,
    -- Window function for ranking within categories
    RANK() OVER (
        PARTITION BY em.PrimaryTagCategory 
        ORDER BY em.NetScore DESC, em.TitleComplexity DESC NULLS LAST
    ) AS CategoryRank,
    -- Complex calculation with conditional logic
    CASE 
        WHEN em.AnswerCount >= 3 AND ta.AnswerScore >= 10 THEN 
            em.ViewCount * (em.NetScore / em.EffectiveAnswerCount)
        WHEN em.CommentCount > 15 THEN 
            em.ViewCount * 0.5 + em.NetScore * 2
        ELSE 
            COALESCE(em.ViewCount, 0) + NULLIF(em.NetScore, 0)
    END AS EngagementScore,
    -- String aggregation with filtering
    (SELECT STRING_AGG(DISTINCT ph.UserDisplayName, ', ' ORDER BY ph.CreationDate DESC)
     FROM PostHistory ph
     WHERE ph.PostId = em.PostId 
       AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Title, body, or tags edited
       AND ph.UserId IS NOT NULL
     GROUP BY ph.PostId
     HAVING COUNT(*) > 1) AS RecentEditors,
    -- Correlated subquery for close reason analysis
    (SELECT crt.Name
     FROM PostHistory ph2
     INNER JOIN CloseReasonTypes crt ON ph2.Comment::smallint = crt.Id
     WHERE ph2.PostId = em.PostId 
       AND ph2.PostHistoryTypeId = 10  -- Post Closed
     ORDER BY ph2.CreationDate DESC
     LIMIT 1) AS LastCloseReason
FROM EngagementMetrics em
INNER JOIN ActiveUsers au ON em.OwnerUserId = au.UserId
LEFT JOIN TopAnswers ta ON em.PostId = ta.ParentId AND ta.AnswerRank = 1
LEFT JOIN VotePatterns vp ON au.UserId = vp.UserId
WHERE em.NetScore > 5 
  AND (em.TitleComplexity > 20 OR em.PrimaryTagCategory IN ('Java', 'Python'))
  AND em.PostStatus = 'Open'
   -- Complex predicate with set operations
   AND em.PostId NOT IN (
       SELECT pl.RelatedPostId 
       FROM PostLinks pl 
       WHERE pl.LinkTypeId = 3  -- Duplicate links
         AND pl.CreationDate >= CURRENT_DATE - INTERVAL '3 months'
   )
ORDER BY EngagementScore DESC, CategoryRank ASC
LIMIT 100;
