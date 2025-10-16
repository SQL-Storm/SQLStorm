-- {"query": "150.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2536} 
WITH
-- posts authored by users with basic classification
user_posts AS (
  SELECT p.*, u.Reputation, u.DisplayName AS OwnerName
  FROM Posts p
  JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
-- explode tags like '<tag1><tag2>' into rows
tag_exploded AS (
  SELECT q.Id AS QuestionId,
         trim(both '<>' FROM unnest(string_to_array(substring(q.Tags FROM 2 FOR char_length(q.Tags)-2), '><'))) AS Tag
  FROM Posts q
  WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL AND q.Tags <> ''
),
-- badge aggregates per user
badge_aggr AS (
  SELECT b.UserId,
         COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
         COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
         COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
         COUNT(*) AS TotalBadges,
         BOOL_OR(b.TagBased) AS HasTagBadges
  FROM Badges b
  GROUP BY b.UserId
),
-- answer statistics per user
answer_metrics AS (
  SELECT a.OwnerUserId AS UserId,
         COUNT(*) FILTER (WHERE a.PostTypeId = 2) AS AnswerCount,
         COALESCE(AVG(NULLIF(a.Score,0)),0) AS AvgAnswerScoreNonZero,
         COALESCE(AVG(a.Score),0) AS AvgAnswerScoreAll,
         SUM(CASE WHEN a.ParentId IS NOT NULL AND a.CreationDate IS NOT NULL THEN 1 ELSE 0 END) AS LinkedToQuestionCount,
         percentile_disc(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianAnswerScore
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.OwnerUserId
),
-- question-level metrics including correlated subquery for time to first answer
question_metrics AS (
  SELECT q.Id AS QuestionId,
         q.OwnerUserId AS UserId,
         q.CreationDate,
         q.Score AS QuestionScore,
         q.ViewCount,
         q.AnswerCount,
         -- time to first answer in seconds, NULL if no answers
         (SELECT EXTRACT(EPOCH FROM MIN(a.CreationDate) - q.CreationDate)
          FROM Posts a
          WHERE a.ParentId = q.Id AND a.PostTypeId = 2 AND a.CreationDate IS NOT NULL
         ) AS SecToFirstAnswer,
         -- number of duplicate links pointing to this question (PostLinks where RelatedPostId = q.Id and LinkTypeId = 3)
         (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = q.Id AND pl.LinkTypeId = 3) AS DuplicateTargets
  FROM Posts q
  WHERE q.PostTypeId = 1
),
-- votes summary per post and per user via JOINs and window functions
votes_per_post AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS VoteScore,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteCount,
         COUNT(*) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
-- user-level aggregates combining posts, answers, questions, badges, votes, tags
user_summary AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         COALESCE(am.AnswerCount,0) AS AnswerCount,
         COALESCE(qm.QuestionsAsked,0) AS QuestionsAsked,
         COALESCE(bag.TotalBadges,0) AS TotalBadges,
         COALESCE(bag.GoldBadges,0) AS GoldBadges,
         COALESCE(bag.SilverBadges,0) AS SilverBadges,
         COALESCE(bag.BronzeBadges,0) AS BronzeBadges,
         -- use windowed averages to capture recent activity: avg score of last 5 answers
         COALESCE(
           (
             SELECT AVG(s.Score)
             FROM (
               SELECT p.Score
               FROM Posts p
               WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
               ORDER BY p.CreationDate DESC
               LIMIT 5
             ) s
           ), 0) AS AvgLast5AnswerScores,
         -- tag reach: count distinct tags across user's questions
         COALESCE(
           (SELECT COUNT(DISTINCT te.Tag) FROM tag_exploded te WHERE te.QuestionId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1))
         ,0) AS DistinctQuestionTags,
         -- windowed rank by reputation
         RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
  FROM Users u
  LEFT JOIN answer_metrics am ON am.UserId = u.Id
  LEFT JOIN badge_aggr bag ON bag.UserId = u.Id
  LEFT JOIN (
    SELECT q.OwnerUserId, COUNT(*) AS QuestionsAsked
    FROM Posts q
    WHERE q.PostTypeId = 1
    GROUP BY q.OwnerUserId
  ) qm ON qm.OwnerUserId = u.Id
),
-- assemble a complex per-user profile with joins to posts, votes and comment counts
user_profile AS (
  SELECT us.*,
         COALESCE(SUM(vp.VoteScore),0) AS NetPostVoteScore,
         COALESCE(SUM(vp.TotalVotes),0) AS TotalPostVotes,
         COALESCE(SUM(c.CommentCount),0) AS TotalCommentsOnPosts,
         -- calculate an engagement index with complicated expression and NULL logic
         (
           (us.Reputation::numeric + GREATEST(us.AnswerCount, 0) * 5
            + us.DistinctQuestionTags * 3
            + COALESCE(us.TotalBadges,0) * 10)
           * CASE WHEN us.AvgLast5AnswerScores IS NULL THEN 0.9 ELSE 1 + LEAST(us.AvgLast5AnswerScores / NULLIF(GREATEST(us.Reputation,1),0), 2) END
         )::numeric(18,4) AS EngagementIndex
  FROM user_summary us
  LEFT JOIN Posts p ON p.OwnerUserId = us.UserId
  LEFT JOIN votes_per_post vp ON vp.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) c ON c.PostId = p.Id
  GROUP BY us.UserId, us.DisplayName, us.Reputation, us.CreationDate, us.LastAccessDate,
           us.AnswerCount, us.QuestionsAsked, us.TotalBadges, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
           us.AvgLast5AnswerScores, us.DistinctQuestionTags, us.ReputationRank
)
-- final selection: combine top reputations with interesting edge-case filters, include window deltas, correlate with recent activity, and present union of two different ranking approaches
SELECT *
FROM (
  -- Part A: top 50 by EngagementIndex with extra window analytics
  SELECT up.*,
         ROW_NUMBER() OVER (ORDER BY up.EngagementIndex DESC) AS EngagementRank,
         LEAD(up.EngagementIndex) OVER (ORDER BY up.EngagementIndex DESC) AS NextEngagementIndex,
         LAG(up.EngagementIndex) OVER (ORDER BY up.EngagementIndex DESC) AS PrevEngagementIndex,
         CASE
           WHEN up.TotalBadges = 0 THEN 'NoBadges'
           WHEN up.GoldBadges > 0 THEN 'HasGold'
           WHEN up.SilverBadges > 0 THEN 'HasSilver'
           ELSE 'BronzeOnly'
         END AS BadgeProfile,
         -- boolean heuristics using NULL logic
         (up.LastAccessDate > up.CreationDate + INTERVAL '365 days') AS LongActiveSinceCreation,
         -- string expression combining truncated display name and id
         substring(coalesce(up.DisplayName,'<anon>') from 1 for 18) || '#' || up.UserId::text AS CompactHandle,
         -- correlated check: whether the user has at least one question with a duplicate target
         EXISTS (
           SELECT 1 FROM question_metrics qm WHERE qm.UserId = up.UserId AND qm.DuplicateTargets > 0
         ) AS HasDuplicateTargets
  FROM user_profile up
  ORDER BY up.EngagementIndex DESC
  LIMIT 50

  UNION ALL

  -- Part B: top 50 by Reputation but exclude those in Part A to force set logic and heavier planning
  SELECT upb.*,
         ROW_NUMBER() OVER (ORDER BY upb.Reputation DESC) AS ReputationSortRank,
         NULL::numeric(18,4) AS NextEngagementIndex,
         NULL::numeric(18,4) AS PrevEngagementIndex,
         'ReputationTop' AS BadgeProfile,
         (upb.LastAccessDate IS NULL) AS LongActiveSinceCreation,
         substring(coalesce(upb.DisplayName,'<anon>') from 1 for 18) || '#' || upb.UserId::text AS CompactHandle,
         FALSE AS HasDuplicateTargets
  FROM user_profile upb
  WHERE upb.UserId NOT IN (
    SELECT up2.UserId FROM user_profile up2 ORDER BY up2.EngagementIndex DESC LIMIT 50
  )
  ORDER BY upb.Reputation DESC
  LIMIT 50
) final
-- final filtering demonstrating complicated predicate with NULL logic, string ops and set operator
WHERE
  -- must have some activity or be a high reputation user; prefer those with non-zero engagement
  (final.EngagementIndex > 0 OR final.Reputation > 10000)
  AND (
    -- include only those whose compact handle contains an alphabetic char or who have badges
    final.CompactHandle ~ '[A-Za-z]' OR final.TotalBadges > 0
  )
ORDER BY COALESCE(final.EngagementRank, final.ReputationSortRank, 999999) ASC,
         final.Reputation DESC,
         final.EngagementIndex DESC
;