-- {"query": "37033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2321} 
WITH
-- prolific contributors: users with high combined activity score
user_activity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS PostsCount,
         COUNT(DISTINCT c.Id) AS CommentsCount,
         COUNT(DISTINCT b.Id) AS BadgesCount,
         COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
         COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
         (COALESCE(u.Reputation,0) * 0.4
          + COALESCE(COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1,2)),0) * 3
          + COALESCE(COUNT(DISTINCT c.Id),0) * 1
          + COALESCE(COUNT(DISTINCT b.Id),0) * 2
          + COALESCE(COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2),0) * 0.2
          - COALESCE(COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3),0) * 0.5
         ) AS ActivityScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- top tags by popularity and engagement (score-weighted)
question_tags AS (
  SELECT
    t.TagName,
    t.Id AS TagId,
    t.Count AS TagCount,
    COUNT(q.Id) AS QuestionsCount,
    SUM(COALESCE(q.ViewCount,0)) AS TotalViews,
    SUM(COALESCE(q.Score,0)) AS TotalScore,
    SUM(COALESCE(q.AnswerCount,0)) AS TotalAnswers
  FROM Tags t
  LEFT JOIN Posts q ON q.PostTypeId = 1 AND q.Tags IS NOT NULL
    AND POSITION(CONCAT('<', t.TagName, '>') IN q.Tags) > 0
  GROUP BY t.Id, t.TagName, t.Count
),
-- compute median response time for questions per tag
question_answers AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate AS QuestionCreated,
         a.Id AS AnswerId,
         a.CreationDate AS AnswerCreated,
         t.TagName
  FROM Posts q
  JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  JOIN question_tags t ON POSITION(CONCAT('<', t.TagName, '>') IN q.Tags) > 0
  WHERE q.PostTypeId = 1 AND q.CreationDate IS NOT NULL AND a.CreationDate IS NOT NULL
),
answer_latency AS (
  SELECT TagName,
         QuestionId,
         MIN(EXTRACT(EPOCH FROM (AnswerCreated - QuestionCreated))/3600.0) AS FirstAnswerHours,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (AnswerCreated - QuestionCreated))/3600.0) AS MedianAnswerHours
  FROM question_answers
  GROUP BY TagName, QuestionId
),
tag_latency_summary AS (
  SELECT
    qt.TagName,
    qt.TagCount,
    qt.QuestionsCount,
    qt.TotalViews,
    qt.TotalScore,
    qt.TotalAnswers,
    AVG(al.FirstAnswerHours) AS AvgFirstAnswerHours,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY al.MedianAnswerHours) AS MedianOfMediansHours,
    COUNT(al.QuestionId) AS QuestionsWithAnswers
  FROM question_tags qt
  LEFT JOIN answer_latency al ON al.TagName = qt.TagName
  GROUP BY qt.TagName, qt.TagCount, qt.QuestionsCount, qt.TotalViews, qt.TotalScore, qt.TotalAnswers
),
-- interesting post link graph metrics
post_link_graph AS (
  SELECT
    pl.PostId,
    p.Title,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS OutgoingLinks,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS OutgoingDuplicates,
    COUNT(pl2.Id) FILTER (WHERE pl2.LinkTypeId = 1) AS IncomingLinks,
    COUNT(pl2.Id) FILTER (WHERE pl2.LinkTypeId = 3) AS IncomingDuplicates
  FROM PostLinks pl
  JOIN Posts p ON p.Id = pl.PostId
  LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = pl.PostId
  GROUP BY pl.PostId, p.Title
),
-- hottest unanswered questions that are old but still receiving activity
stalled_questions AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate,
         q.LastActivityDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         q.CommentCount,
         COALESCE(q.ViewCount,0)::float / NULLIF(EXTRACT(EPOCH FROM (NOW() - q.CreationDate))/86400.0,0) AS ViewsPerDay,
         GREATEST(0, q.AnswerCount) AS Answers,
         u.DisplayName AS OwnerName
  FROM Posts q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  WHERE q.PostTypeId = 1
    AND (q.AnswerCount = 0 OR q.AcceptedAnswerId IS NULL)
    AND q.CreationDate < NOW() - INTERVAL '90 days'
),
-- aggregate combined benchmark result
ranked_tags AS (
  SELECT l.*,
         (l.QuestionsCount * 0.3 + l.TotalViews * 0.25 + l.TotalScore * 0.2 + GREATEST(0, (1.0 / NULLIF(l.AvgFirstAnswerHours,0))) * 50 + GREATEST(0, (1.0 / NULLIF(l.MedianOfMediansHours,0))) * 30) AS TagHotnessScore
  FROM tag_latency_summary l
)
SELECT
  now() AS BenchmarkRunAt,
  -- Top 10 users by activity score with some recent contributions
  (SELECT json_agg(row_to_json(u2)) FROM (
     SELECT ua.UserId, ua.DisplayName, ua.Reputation, ua.PostsCount, ua.CommentsCount, ua.BadgesCount, ROUND(ua.ActivityScore,2) AS ActivityScore,
            (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.CreationDate > NOW() - INTERVAL '30 days') AS RecentPosts30d
     FROM user_activity ua
     WHERE ua.ActivityScore IS NOT NULL
     ORDER BY ua.ActivityScore DESC
     LIMIT 10
  ) u2) AS TopUsers,
  -- Top 15 tags by hotness score with latency info
  (SELECT json_agg(row_to_json(t2)) FROM (
     SELECT rt.TagName, rt.TagCount, rt.QuestionsCount, rt.TotalViews, rt.TotalScore, rt.TotalAnswers,
            ROUND(rt.AvgFirstAnswerHours::numeric,2) AS AvgFirstAnswerHours,
            ROUND(rt.MedianOfMediansHours::numeric,2) AS MedianOfMediansHours,
            ROUND(rt.TagHotnessScore::numeric,2) AS TagHotnessScore
     FROM ranked_tags rt
     ORDER BY rt.TagHotnessScore DESC
     LIMIT 15
  ) t2) AS TopTags,
  -- sample graph anomalies: posts with many incoming duplicates but low score
  (SELECT json_agg(row_to_json(g2)) FROM (
     SELECT pl.PostId, pl.Title, pl.IncomingDuplicates, pl.IncomingLinks, pl.OutgoingDuplicates, pl.OutgoingLinks, p.Score, p.ViewCount
     FROM post_link_graph pl
     JOIN Posts p ON p.Id = pl.PostId
     WHERE pl.IncomingDuplicates >= 3
     ORDER BY pl.IncomingDuplicates DESC, p.Score ASC
     LIMIT 20
  ) g2) AS DuplicateTargets,
  -- stalled question samples
  (SELECT json_agg(row_to_json(sq)) FROM (
     SELECT sq.QuestionId, sq.Title, sq.CreationDate, sq.LastActivityDate, sq.Score, ROUND(sq.ViewsPerDay::numeric,2) AS ViewsPerDay, sq.Answers, sq.OwnerName
     FROM stalled_questions sq
     ORDER BY sq.ViewsPerDay DESC NULLS LAST, sq.Score DESC
     LIMIT 25
  ) sq) AS StalledPopularQuestions,
  -- heavy join stress: produce distribution of votes by tag for recent month
  (SELECT json_agg(row_to_json(vt)) FROM (
     SELECT qt.TagName,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
            COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
            COUNT(v.Id) AS TotalVotes,
            ROUND((COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)::numeric / NULLIF(COUNT(v.Id),0)),3) AS UpVoteRatio
     FROM question_tags qt
     JOIN Posts p ON p.PostTypeId = 1 AND POSITION(CONCAT('<', qt.TagName, '>') IN p.Tags) > 0
     JOIN Votes v ON v.PostId = p.Id AND v.CreationDate > NOW() - INTERVAL '30 days'
     GROUP BY qt.TagName
     HAVING COUNT(v.Id) > 10
     ORDER BY TotalVotes DESC
     LIMIT 30
  ) vt) AS TagVoteDistribution,
  -- final stress: cross-sectional stats combining many tables
  (SELECT row_to_json(summary) FROM (
     SELECT
       (SELECT COUNT(*) FROM Posts) AS TotalPosts,
       (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) AS TotalQuestions,
       (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) AS TotalAnswers,
       (SELECT COUNT(*) FROM Users WHERE CreationDate > NOW() - INTERVAL '30 days') AS NewUsers30d,
       (SELECT COUNT(*) FROM Votes WHERE CreationDate > NOW() - INTERVAL '30 days') AS RecentVotes30d,
       (SELECT COUNT(*) FROM Comments WHERE CreationDate > NOW() - INTERVAL '30 days') AS RecentComments30d,
       (SELECT COUNT(*) FROM PostLinks WHERE CreationDate > NOW() - INTERVAL '365 days') AS LinksLastYear,
       (SELECT COUNT(*) FROM Badges WHERE Date > NOW() - INTERVAL '365 days') AS BadgesLastYear
  ) summary) AS GlobalCounts;