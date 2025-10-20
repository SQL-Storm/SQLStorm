-- {"query": "37004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1644} 
WITH
-- recent active questions with tag arrays
Questions AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
         COALESCE(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><'), '{}') AS TagArray,
         p.AnswerCount, p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > now() - interval '3 years'
),
-- top answer for each question by score then creation date
TopAnswers AS (
  SELECT a.ParentId AS QuestionId, a.Id AS AnswerId, a.OwnerUserId AS AnswerOwner,
         a.Score AS AnswerScore, a.CreationDate AS AnswerCreation
  FROM Posts a
  JOIN (
    SELECT ParentId, max(Score) AS MaxScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) m ON a.ParentId = m.ParentId AND a.Score = m.MaxScore
  WHERE a.PostTypeId = 2
),
-- aggregate badge summary per user
UserBadges AS (
  SELECT b.UserId,
         count(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
         count(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
         count(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
         count(*) AS TotalBadges,
         max(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
-- votes breakdown per post (useful for heavy aggregation)
PostVotes AS (
  SELECT v.PostId,
         count(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
         count(*) FILTER (WHERE v.VoteTypeId = 8) AS BountyStarts,
         count(*) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
-- comment heat per post and per user in last year
RecentComments AS (
  SELECT c.PostId, c.UserId,
         count(*) AS CommentsOnPostByUser,
         max(c.CreationDate) AS LastCommentAt
  FROM Comments c
  WHERE c.CreationDate > now() - interval '1 year'
  GROUP BY c.PostId, c.UserId
),
-- tag popularity derived from questions in timeframe
TagPopularity AS (
  SELECT tag AS TagName, count(*) AS QuestionCount,
         avg(q.Score) AS AvgScore, sum(q.ViewCount) AS TotalViews
  FROM Questions q, unnest(q.TagArray) AS tag
  GROUP BY tag
  ORDER BY QuestionCount DESC
  LIMIT 200
),
-- compute question similarity by shared tags (pairwise) - heavy join for benchmarking
QuestionTagPairs AS (
  SELECT q1.Id AS Q1, q2.Id AS Q2,
         array_length(array(SELECT unnest(q1.TagArray) INTERSECT SELECT unnest(q2.TagArray)),1) AS SharedTagCount
  FROM Questions q1
  JOIN Questions q2 ON q1.Id < q2.Id
  WHERE (array_length(q1.TagArray,1) IS NOT NULL AND array_length(q2.TagArray,1) IS NOT NULL)
),
TopSimilarPairs AS (
  SELECT Q1, Q2, SharedTagCount
  FROM QuestionTagPairs
  WHERE SharedTagCount IS NOT NULL AND SharedTagCount > 0
  ORDER BY SharedTagCount DESC, Q1, Q2
  LIMIT 1000
),
-- enrich questions with top answer, votes and owner badge summary
EnrichedQuestions AS (
  SELECT q.*,
         ta.AnswerId, ta.AnswerOwner, ta.AnswerScore,
         pv.UpVotes, pv.DownVotes, pv.Favorites, pv.TotalVotes,
         ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBadges
  FROM Questions q
  LEFT JOIN TopAnswers ta ON q.Id = ta.QuestionId
  LEFT JOIN PostVotes pv ON q.Id = pv.PostId
  LEFT JOIN UserBadges ub ON q.OwnerUserId = ub.UserId
),
-- compute movers: questions with large relative score increase in last 6 months (score delta via PostHistory edits)
RecentScoreDeltas AS (
  SELECT ph.PostId AS QuestionId,
         max(CASE WHEN ph.CreationDate <= now() - interval '6 months' THEN (ph.Text::json->>'score')::int END) AS ScoreSixMonthsAgo,
         max(CASE WHEN ph.CreationDate > now() - interval '6 months' THEN (ph.Text::json->>'score')::int END) AS ScoreRecent
  FROM PostHistory ph
  WHERE ph.PostId IN (SELECT Id FROM Questions)
    AND ph.PostHistoryTypeId IN (2,5) -- initial/body edits may contain score metadata if exported; best-effort
  GROUP BY ph.PostId
),
Movers AS (
  SELECT q.Id, q.Title, q.Score, rd.ScoreSixMonthsAgo, rd.ScoreRecent,
         CASE
           WHEN rd.ScoreSixMonthsAgo IS NULL AND rd.ScoreRecent IS NOT NULL THEN rd.ScoreRecent
           WHEN rd.ScoreSixMonthsAgo IS NOT NULL AND rd.ScoreRecent IS NULL THEN q.Score - rd.ScoreSixMonthsAgo
           ELSE COALESCE(rd.ScoreRecent, q.Score) - COALESCE(rd.ScoreSixMonthsAgo, 0)
         END AS ScoreDelta
  FROM Questions q
  LEFT JOIN RecentScoreDeltas rd ON q.Id = rd.QuestionId
  WHERE COALESCE(rd.ScoreRecent, q.Score) - COALESCE(rd.ScoreSixMonthsAgo, 0) > 5
),
-- final combined heavy result set for benchmarking: for each enriched question, include top similar peers and tag popularity aggregates
Final AS (
  SELECT eq.Id AS QuestionId, eq.Title, eq.OwnerUserId, eq.CreationDate, eq.Score AS CurrentScore,
         eq.ViewCount, eq.AnswerCount, eq.CommentCount,
         eq.AnswerId, eq.AnswerOwner, eq.AnswerScore,
         eq.UpVotes, eq.DownVotes, eq.Favorites, eq.TotalVotes,
         eq.GoldBadges, eq.SilverBadges, eq.BronzeBadges, eq.TotalBadges,
         tp.TagName AS TopTag, tp.QuestionCount AS TagPopularity,
         ms.ScoreDelta AS RecentScoreDelta,
         array(
           SELECT json_build_object('PeerQ', q2.Id, 'Title', q2.Title, 'SharedTags', p.SharedTagCount)
           FROM TopSimilarPairs p
           JOIN Posts q2 ON q2.Id = CASE WHEN p.Q1 = eq.Id THEN p.Q2 WHEN p.Q2 = eq.Id THEN p.Q1 ELSE NULL END
           WHERE p.Q1 = eq.Id OR p.Q2 = eq.Id
           ORDER BY p.SharedTagCount DESC
           LIMIT 5
         ) AS TopSimilarQuestions
  FROM EnrichedQuestions eq
  LEFT JOIN LATERAL (
    SELECT tag AS TopTag
    FROM unnest(eq.TagArray) AS tag
    ORDER BY (SELECT QuestionCount FROM TagPopularity tp2 WHERE tp2.TagName = tag) DESC NULLS LAST
    LIMIT 1
  ) tp1 ON true
  LEFT JOIN TagPopularity tp ON tp.TagName = tp1.TopTag
  LEFT JOIN Movers ms ON ms.Id = eq.Id
)
SELECT *
FROM Final
ORDER BY RecentScoreDelta DESC NULLS LAST, TagPopularity DESC NULLS LAST, CurrentScore DESC
LIMIT 500;