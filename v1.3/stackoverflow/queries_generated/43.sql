-- {"query": "43.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2335} 
WITH
-- recent active posts with exploded tags and basic metrics
RecentPosts AS (
  SELECT p.Id, p.PostTypeId, p.ParentId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
         p.Title, p.Tags,
         COALESCE(p.AnswerCount,0) AS AnswerCount,
         COALESCE(p.CommentCount,0) AS CommentCount,
         COALESCE(p.FavoriteCount,0) AS FavoriteCount,
         -- extract tags into rows (Postgres style); if DB lacks string_to_array, this is for benchmark complexity
         regexp_split_to_table(substring(p.Tags from 2 for char_length(p.Tags)-2), E'\\><') AS Tag
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '2 years'
    AND p.PostTypeId IN (1,2) -- questions and answers
),
-- per-post aggregated vote statistics with conditional expressions and NULL handling
PostVotes AS (
  SELECT v.PostId,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 2)        AS UpVotes,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 3)        AS DownVotes,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 5)        AS Favorites,
         COUNT(*) FILTER (WHERE v.VoteTypeId IN (8,9))   AS BountyEvents,
         SUM(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) AS BountySum,
         MIN(v.CreationDate)                              AS FirstVoteDate,
         MAX(v.CreationDate)                              AS LastVoteDate,
         COUNT(*)                                          AS TotalVotes
  FROM Votes v
  WHERE v.CreationDate >= now() - interval '5 years'
  GROUP BY v.PostId
),
-- compute recent activity window stats per user using window functions and frame clauses
UserActivity AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate,
         COUNT(DISTINCT rp.Id) FILTER (WHERE rp.PostTypeId = 1) OVER (PARTITION BY u.Id)         AS QuestionsAuthored,
         COUNT(DISTINCT rp.Id) FILTER (WHERE rp.PostTypeId = 2) OVER (PARTITION BY u.Id)         AS AnswersAuthored,
         SUM(COALESCE(pv.TotalVotes,0)) OVER (PARTITION BY u.Id)                               AS VotesOnTheirPosts,
         ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC)                   AS RecentAccessSeq
  FROM Users u
  LEFT JOIN Posts rp ON rp.OwnerUserId = u.Id AND rp.CreationDate >= now() - interval '5 years'
  LEFT JOIN PostVotes pv ON pv.PostId = rp.Id
  WHERE u.CreationDate <= now()
),
-- correlate each question with its accepted answer stats and sibling answers comparison
AnswerComparisons AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.OwnerUserId AS AnswererId,
         a.Score AS AnswerScore,
         a.CreationDate AS AnswerCreated,
         q.Id AS QuestionIdRef,
         q.Title AS QuestionTitle,
         q.Score AS QuestionScore,
         -- rank answers per question by score then by creation date
         RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
         COUNT(*) OVER (PARTITION BY a.ParentId) AS AnswersPerQuestion,
         -- correlated subquery: count comments on this answer
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id AND c.CreationDate >= a.CreationDate - interval '30 days') AS RecentCommentCount,
         -- correlated subquery: find if this answer's owner has a higher reputation than question owner
         CASE WHEN a.OwnerUserId IS NOT NULL AND q.OwnerUserId IS NOT NULL
              THEN (SELECT COALESCE(u2.Reputation,0) > COALESCE(u1.Reputation,0)
                    FROM Users u1 JOIN Users u2 ON u2.Id = a.OwnerUserId WHERE u1.Id = q.OwnerUserId LIMIT 1)
              ELSE NULL END AS IsAnswererHigherRep
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  WHERE a.PostTypeId = 2
),
-- compute tag-level rolling popularity and complex string-based metrics
TagMetrics AS (
  SELECT rp.Tag,
         COUNT(DISTINCT rp.Id) AS PostsWithTag,
         AVG(rp.Score) AS AvgScore,
         SUM(CASE WHEN rp.PostTypeId = 1 THEN COALESCE(pv.UpVotes,0) - COALESCE(pv.DownVotes,0) ELSE 0 END) AS NetVotesOnQuestions,
         MAX(rp.CreationDate) AS MostRecentPost,
         -- string expression: tag name fingerprint (xor of ascii codes mod prime)
         (sum(ascii(substring(regexp_replace(rp.Tag,'[^a-z0-9]','','gi'), i, 1))::int) % 997) AS SimpleFingerprint
  FROM RecentPosts rp
  LEFT JOIN PostVotes pv ON pv.PostId = rp.Id
  CROSS JOIN LATERAL generate_series(1, greatest(char_length(regexp_replace(rp.Tag,'[^a-z0-9]','','gi')),1)) AS s(i)
  GROUP BY rp.Tag
),
-- produce a union of heavy-weight sets: top questions, top answers, and intriguing cross-links
TopSets AS (
  SELECT 'TopQuestions' AS SetName, p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.Tags, NULL::int AS ParentId, p.CreationDate
  FROM Posts p
  LEFT JOIN PostVotes pv ON pv.PostId = p.Id
  WHERE p.PostTypeId = 1
  ORDER BY (p.Score * 3 + COALESCE(pv.UpVotes,0) - COALESCE(pv.DownVotes,0) + (p.ViewCount/100)::int) DESC
  LIMIT 200

  UNION ALL

  SELECT 'TopAnswers' AS SetName, a.Id, NULL::varchar AS Title, a.OwnerUserId, a.Score, NULL::int AS ViewCount, NULL::varchar AS Tags, a.ParentId, a.CreationDate
  FROM Posts a
  WHERE a.PostTypeId = 2
  ORDER BY a.Score DESC
  LIMIT 200

  UNION ALL

  SELECT 'LinkedPosts' AS SetName, pl.RelatedPostId AS Id, p2.Title, p2.OwnerUserId, p2.Score, p2.ViewCount, p2.Tags, p2.ParentId, pl.CreationDate
  FROM PostLinks pl
  JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE pl.CreationDate >= now() - interval '1 year' AND pl.LinkTypeId = 1
  ORDER BY pl.CreationDate DESC
  LIMIT 200
),
-- final enrichment: join everything, apply complex predicates and compute final scoring
Enriched AS (
  SELECT ts.*,
         COALESCE(pv.UpVotes,0) AS UpVotes, COALESCE(pv.DownVotes,0) AS DownVotes, COALESCE(pv.BountySum,0) AS BountySum,
         COALESCE(tm.PostsWithTag,0) AS TagPostCount,
         COALESCE(uc.QuestionsAuthored,0) AS AuthorQuestions,
         COALESCE(uc.AnswersAuthored,0) AS AuthorAnswers,
         COALESCE(ae.AnswerRank, NULL) AS AnswerRank,
         COALESCE(ae.AnswersPerQuestion, 0) AS AnswersPerQuestion,
         -- complex computed score combining recency, community signals, author reputation, and tag popularity
         (
           (COALESCE(ts.Score,0) * 10)
           + (COALESCE(pv.UpVotes,0) * 5)
           - (COALESCE(pv.DownVotes,0) * 8)
           + (COALESCE(pv.TotalVotes,0) * 2)
           + (CASE WHEN ts.CreationDate >= now() - interval '30 days' THEN 200 ELSE 0 END)
           + (CASE WHEN ts.PostTypeId = 1 AND ts.AnswerCount > 0 THEN 150 ELSE 0 END)
           + (COALESCE(uc.Reputation,0)/100)
           + (COALESCE(tm.PostsWithTag,0) * 0.1)
           - (CASE WHEN ts.Tags IS NULL THEN 50 ELSE 0 END)
           + (CASE WHEN ts.ParentId IS NOT NULL AND ae.AnswerRank = 1 THEN 75 ELSE 0 END)
         )::numeric AS CompositeScore,
         -- null logic and text operations: normalized title and snippet
         NULLIF(trim(coalesce(ts.Title, '')), '') AS NormalizedTitle,
         CASE WHEN ts.Title IS NOT NULL THEN left(replace(replace(ts.Title, E'\n', ' '), E'\t',' '), 200) ELSE NULL END AS TitleSnippet,
         -- flag suspicious posts: low rep authors with high bounty or sudden vote bursts
         (CASE WHEN COALESCE(ts.OwnerUserId,-1) = -1 THEN 'community' WHEN COALESCE(uc.Reputation,0) < 50 AND COALESCE(pv.TotalVotes,0) > 20 THEN 'suspicious' ELSE 'ok' END) AS TrustLabel
  FROM TopSets ts
  LEFT JOIN PostVotes pv ON pv.PostId = ts.Id
  LEFT JOIN RecentPosts rp ON rp.Id = ts.Id
  LEFT JOIN TagMetrics tm ON tm.Tag = rp.Tag
  LEFT JOIN Users uc ON uc.Id = ts.OwnerUserId
  LEFT JOIN AnswerComparisons ae ON ae.AnswerId = ts.Id
)
-- final selection with ordering, windowed percentile, and a HAVING style filter via QUALIFY-like construct emulation
SELECT e.SetName, e.Id, e.Title, e.NormalizedTitle, e.TitleSnippet, e.OwnerUserId, e.Reputation, e.UpVotes, e.DownVotes, e.BountySum,
       e.TagPostCount, e.AuthorQuestions, e.AuthorAnswers, e.AnswersPerQuestion, e.AnswerRank,
       e.CompositeScore,
       PERCENT_RANK() OVER (PARTITION BY e.SetName ORDER BY e.CompositeScore) AS CompositePercentile,
       ROW_NUMBER() OVER (PARTITION BY e.SetName ORDER BY e.CompositeScore DESC, e.UpVotes DESC, e.CreationDate DESC) AS RankWithinSet
FROM Enriched e
WHERE e.CompositeScore IS NOT NULL
  AND (e.CompositeScore > 100 OR e.TrustLabel = 'suspicious')
ORDER BY e.SetName, CompositeScore DESC, e.UpVotes DESC
LIMIT 500;