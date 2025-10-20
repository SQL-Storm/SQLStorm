-- {"query": "37087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2318} 
WITH
-- active users: created before cutoff and with at least one post/comment/vote in period
activity AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate,
         u.DisplayName,
         u.Location,
         COALESCE(pq.QCount,0) AS QuestionsPosted,
         COALESCE(pa.ACount,0) AS AnswersPosted,
         COALESCE(c.Comments,0) AS CommentsMade,
         COALESCE(v.Votes,0) AS VotesCast,
         COALESCE(b.Badges,0) AS BadgesEarned,
         GREATEST(
           COALESCE(pq.LastPost, '1970-01-01'::timestamp),
           COALESCE(pa.LastPost, '1970-01-01'::timestamp),
           COALESCE(c.LastComment, '1970-01-01'::timestamp),
           COALESCE(v.LastVote, '1970-01-01'::timestamp)
         ) AS LastActivity
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS QCount, MAX(CreationDate) AS LastPost
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) pq ON pq.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS ACount, MAX(CreationDate) AS LastPost
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
  ) pa ON pa.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS Comments, MAX(CreationDate) AS LastComment
    FROM Comments
    GROUP BY UserId
  ) c ON c.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS Votes, MAX(CreationDate) AS LastVote
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS Badges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  WHERE u.CreationDate < now() - INTERVAL '30 days'
),
-- richest tags per user via answers to tagged questions (weight by answer score and question viewcount)
user_tag_impact AS (
  SELECT p.OwnerUserId AS UserId,
         unnest(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><')) AS Tag,
         SUM(GREATEST(a.Score,0) * GREATEST(q.ViewCount,100)) AS ImpactScore,
         COUNT(*) AS AnsweredToQuestions
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  JOIN Posts p ON p.Id = a.Id -- alias to reference owner
  WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL AND q.Tags IS NOT NULL
  GROUP BY p.OwnerUserId, Tag
),
-- for each user, top 3 tags by impact
top_tags AS (
  SELECT utt.UserId,
         utt.Tag,
         utt.ImpactScore,
         utt.AnsweredToQuestions,
         ROW_NUMBER() OVER (PARTITION BY utt.UserId ORDER BY utt.ImpactScore DESC) AS rn
  FROM user_tag_impact utt
),
top3_tags AS (
  SELECT UserId,
         json_agg(json_build_object('Tag', Tag, 'Impact', ImpactScore, 'AnsweredQuestions', AnsweredToQuestions) ORDER BY ImpactScore DESC) FILTER (WHERE rn <= 3) AS TopTags
  FROM top_tags
  GROUP BY UserId
),
-- compute answer quality: accepted rate, average score, median score, time-to-accept
answer_metrics AS (
  SELECT a.OwnerUserId AS UserId,
         COUNT(*) FILTER (WHERE a.Id IS NOT NULL) AS Answers,
         COUNT(*) FILTER (WHERE q.AcceptedAnswerId = a.Id) AS AcceptedAnswers,
         AVG(a.Score) AS AvgAnswerScore,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianAnswerScore,
         AVG(EXTRACT(EPOCH FROM (q.AcceptedAnswerId = a.Id)::int * (q.CreationDate - a.CreationDate))) FILTER (WHERE q.AcceptedAnswerId = a.Id) AS AvgTimeToAcceptSeconds
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  WHERE a.PostTypeId = 2
  GROUP BY a.OwnerUserId
),
-- badge distribution and top badges
badge_summary AS (
  SELECT b.UserId,
         COUNT(*) AS BadgeCount,
         COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
         COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
         COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze,
         array_agg(b.Name ORDER BY b.Date DESC)[:5] AS RecentBadges
  FROM Badges b
  GROUP BY b.UserId
),
-- link graph features: number of duplicates marked for user's questions
duplicate_metrics AS (
  SELECT q.OwnerUserId AS UserId,
         COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinksOut,
         COUNT(pl.Id) FILTER (WHERE lt.Name = 'Linked') AS LinkedOut,
         COALESCE(SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END),0) AS DuplicateCount
  FROM Posts q
  LEFT JOIN PostLinks pl ON pl.PostId = q.Id
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE q.PostTypeId = 1
  GROUP BY q.OwnerUserId
),
-- assemble final candidates: active users with at least 5 answers or 3 questions in last year and some activity
candidates AS (
  SELECT a.UserId
  FROM activity a
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS QLastYear
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= now() - INTERVAL '1 year'
    GROUP BY OwnerUserId
  ) qy ON qy.UserId = a.UserId
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, COUNT(*) AS ALastYear
    FROM Posts
    WHERE PostTypeId = 2 AND CreationDate >= now() - INTERVAL '1 year'
    GROUP BY OwnerUserId
  ) ay ON ay.UserId = a.UserId
  WHERE (COALESCE(ay.ALastYear,0) >= 5 OR COALESCE(qy.QLastYear,0) >= 3 OR a.CommentsMade >= 10)
),
-- ranking score combining reputation, activity, answer quality, tags and badges
scored_users AS (
  SELECT act.UserId,
         act.DisplayName,
         act.Reputation,
         act.LastActivity,
         COALESCE(am.Answers,0) AS Answers,
         COALESCE(am.AcceptedAnswers,0) AS AcceptedAnswers,
         COALESCE(am.AvgAnswerScore,0) AS AvgAnswerScore,
         COALESCE(am.MedianAnswerScore,0) AS MedianAnswerScore,
         COALESCE(am.AvgTimeToAcceptSeconds, 1e9) AS AvgTimeToAcceptSeconds,
         COALESCE(tt.TopTags, '[]'::json) AS TopTags,
         COALESCE(bs.BadgeCount,0) AS BadgeCount,
         COALESCE(dm.DuplicateCount,0) AS DuplicateCount,
         -- composite score (arbitrary weights for benchmarking)
         (
           LOG(GREATEST(act.Reputation,1)) * 1.5
           + LEAST(act.QuestionsPosted,50) * 0.5
           + LEAST(act.AnswersPosted,200) * 1.2
           + (COALESCE(am.AcceptedAnswers,0) * 4.0)
           + (COALESCE(am.AvgAnswerScore,0) * 2.0)
           - (LEAST(COALESCE(am.AvgTimeToAcceptSeconds,1e9)/86400.0,365) * 0.05)
           + (COALESCE(bs.Gold,0) * 5.0) + (COALESCE(bs.Silver,0) * 2.0) + (COALESCE(bs.Bronze,0) * 1.0)
           - (GREATEST(COALESCE(dm.DuplicateCount,0)-2,0) * 1.0)
         ) AS CompositeScore
  FROM activity act
  JOIN candidates c ON c.UserId = act.UserId
  LEFT JOIN answer_metrics am ON am.UserId = act.UserId
  LEFT JOIN top3_tags tt ON tt.UserId = act.UserId
  LEFT JOIN badge_summary bs ON bs.UserId = act.UserId
  LEFT JOIN duplicate_metrics dm ON dm.UserId = act.UserId
),
-- expand to include recent high-impact posts and comment sentiment placeholder (simulated via score thresholds)
recent_impact AS (
  SELECT su.*,
         rp.RecentTopPosts,
         rc.RecentCommentsSummary
  FROM scored_users su
  LEFT JOIN (
    SELECT p.OwnerUserId AS UserId,
           json_agg(json_build_object('PostId', p.Id, 'Type', pt.Name, 'Score', p.Score, 'Views', p.ViewCount, 'Title', p.Title) ORDER BY p.Score DESC, p.ViewCount DESC) FILTER (WHERE p.CreationDate >= now() - INTERVAL '180 days')[:5] AS RecentTopPosts
    FROM Posts p
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
    GROUP BY p.OwnerUserId
  ) rp ON rp.UserId = su.UserId
  LEFT JOIN (
    SELECT c.UserId,
           json_agg(json_build_object('CommentId', c.Id, 'PostId', c.PostId, 'Score', c.Score, 'Excerpt', substring(c.Text,1,140))) FILTER (WHERE c.CreationDate >= now() - INTERVAL '180 days')[:10] AS RecentCommentsSummary
    FROM Comments c
    GROUP BY c.UserId
  ) rc ON rc.UserId = su.UserId
)
SELECT
  ri.UserId,
  ri.DisplayName,
  ri.Reputation,
  ri.LastActivity,
  ri.Answers,
  ri.AcceptedAnswers,
  ri.AvgAnswerScore,
  ri.MedianAnswerScore,
  ri.AvgTimeToAcceptSeconds,
  ri.TopTags,
  ri.BadgeCount,
  ri.CompositeScore
FROM recent_impact ri
ORDER BY ri.CompositeScore DESC NULLS LAST, ri.Reputation DESC
LIMIT 50;