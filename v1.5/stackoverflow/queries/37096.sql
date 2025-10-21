-- {"query": "37096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2206} 
WITH
-- top contributors per tag: users with most answers in tag over last 3 years
RecentAnswers AS (
  SELECT p.Id AS AnswerId, p.ParentId AS QuestionId, p.OwnerUserId, p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 2
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    AND p.OwnerUserId IS NOT NULL
),
QuestionTags AS (
  SELECT q.Id AS QuestionId, q.Tags
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.Tags IS NOT NULL
),
AnswerWithTags AS (
  SELECT a.AnswerId, a.OwnerUserId, a.CreationDate,
         qt.Tags,
         -- explode tags string like "<tag1><tag2>" into rows, using regexp
         regexp_split_to_table(substring(qt.Tags,2,length(qt.Tags)-2), '><') AS Tag
  FROM RecentAnswers a
  JOIN QuestionTags qt ON qt.QuestionId = a.QuestionId
),
TagUserStats AS (
  SELECT Tag, OwnerUserId AS UserId,
         count(*) FILTER (WHERE CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year') AS AnswersLastYear,
         count(*) AS AnswersLast3Years,
         min(CreationDate) AS FirstAnswerAt,
         max(CreationDate) AS LastAnswerAt,
         row_number() OVER (PARTITION BY Tag ORDER BY count(*) DESC, max(CreationDate) DESC) AS RankByAnswers
  FROM AnswerWithTags
  GROUP BY Tag, OwnerUserId
),
TopTagContributors AS (
  SELECT Tag, UserId, AnswersLastYear, AnswersLast3Years, FirstAnswerAt, LastAnswerAt
  FROM TagUserStats
  WHERE RankByAnswers <= 50
),
-- compute rich user profile aggregates
UserAggregates AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         coalesce(b.BadgeGold,0) AS GoldBadges,
         coalesce(b.BadgeSilver,0) AS SilverBadges,
         coalesce(b.BadgeBronze,0) AS BronzeBadges,
         coalesce(pq.QuestionsAsked,0) AS QuestionsAsked,
         coalesce(pa.AnswersPosted,0) AS AnswersPosted,
         coalesce(pc.TotalComments,0) AS CommentsMade,
         coalesce(v.UpVotes,0) AS UpVotesCast,
         coalesce(v.DownVotes,0) AS DownVotesCast,
         -- average score of their answers in last 3 years
         coalesce(avg(a.Score) FILTER (WHERE a.PostTypeId=2 AND a.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'),0) AS AvgAnswerScore3y,
         -- most used tag by that user's answers
         tag_top.MostUsedTag
  FROM Users u
  LEFT JOIN (
    SELECT UserId,
           sum(case when Class=1 then 1 else 0 end) AS BadgeGold,
           sum(case when Class=2 then 1 else 0 end) AS BadgeSilver,
           sum(case when Class=3 then 1 else 0 end) AS BadgeBronze
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, count(*) AS QuestionsAsked
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) pq ON pq.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS UserId, count(*) AS AnswersPosted
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
  ) pa ON pa.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, count(*) AS TotalComments
    FROM Comments
    GROUP BY UserId
  ) pc ON pc.UserId = u.Id
  LEFT JOIN (
    SELECT UserId,
           sum(case when VoteTypeId=2 then 1 else 0 end) AS UpVotes,
           sum(case when VoteTypeId=3 then 1 else 0 end) AS DownVotes
    FROM Votes
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId,
           (array_agg(tag ORDER BY cnt DESC))[1] AS MostUsedTag
    FROM (
      SELECT p.OwnerUserId,
             regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><') AS tag,
             count(*) AS cnt
      FROM Posts p
      WHERE p.PostTypeId = 2 AND p.Tags IS NOT NULL
      GROUP BY p.OwnerUserId, tag
    ) s
    GROUP BY OwnerUserId
  ) tag_top ON tag_top.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
           b.BadgeGold, b.BadgeSilver, b.BadgeBronze,
           pq.QuestionsAsked, pa.AnswersPosted, pc.TotalComments, v.UpVotes, v.DownVotes, tag_top.MostUsedTag
),
-- per-tag summary including link/duplicate activity and hotspot questions
TagSummary AS (
  SELECT t.TagName AS Tag,
         t.Count AS TotalQuestionsTagged,
         coalesce(qHot.HotQuestions,0) AS HotQuestionsLastYear,
         coalesce(links.LinkedOut,0) AS LinkedOutCount,
         coalesce(links.Duplicates,0) AS DuplicateCount,
         coalesce(topcontributors.TopContribCount,0) AS DistinctTopContributors
  FROM Tags t
  LEFT JOIN (
    SELECT regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><') AS Tag, count(*) AS HotQuestions
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.LastActivityDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
      AND p.ViewCount > 10000
    GROUP BY regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><')
  ) qHot ON qHot.Tag = t.TagName
  LEFT JOIN (
    SELECT regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><') AS Tag,
           sum(case when pl.LinkTypeId = 1 then 1 else 0 end) AS LinkedOut,
           sum(case when pl.LinkTypeId = 3 then 1 else 0 end) AS Duplicates
    FROM PostLinks pl
    JOIN Posts p ON p.Id = pl.PostId
    WHERE p.PostTypeId = 1
    GROUP BY regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><')
  ) links ON links.Tag = t.TagName
  LEFT JOIN (
    SELECT Tag, count(DISTINCT UserId) AS TopContribCount
    FROM TopTagContributors
    GROUP BY Tag
  ) topcontributors ON topcontributors.Tag = t.TagName
),
-- final heavy-weight join and analytic metrics for benchmarking
BenchmarkPrep AS (
  SELECT ts.Tag,
         ts.TotalQuestionsTagged,
         ts.HotQuestionsLastYear,
         ts.LinkedOutCount,
         ts.DuplicateCount,
         ts.DistinctTopContributors,
         tc.UserId AS TopUserId,
         ua.DisplayName AS TopUserName,
         ua.Reputation AS TopUserRep,
         ua.GoldBadges,
         ua.SilverBadges,
         ua.BronzeBadges,
         ua.QuestionsAsked,
         ua.AnswersPosted,
         ua.CommentsMade,
         ua.UpVotesCast,
         ua.DownVotesCast,
         ua.AvgAnswerScore3y,
         ua.MostUsedTag,
         tc.AnswersLastYear,
         tc.AnswersLast3Years,
         tc.FirstAnswerAt,
         tc.LastAnswerAt,
         -- derive influence score: weighted combination (non-normalized) to maximize compute
         (coalesce(tc.AnswersLast3Years,0) * 3.0
          + coalesce(ua.Reputation,0) * 0.01
          + coalesce(ua.GoldBadges,0) * 5.0
          + coalesce(ua.SilverBadges,0) * 2.0
          + coalesce(ua.BronzeBadges,0) * 0.5
          + coalesce(ua.AvgAnswerScore3y,0) * 1.5
         ) AS InfluenceScore
  FROM TagSummary ts
  LEFT JOIN TopTagContributors tc ON tc.Tag = ts.Tag
  LEFT JOIN UserAggregates ua ON ua.UserId = tc.UserId
),
RankedResults AS (
  SELECT *,
         rank() OVER (PARTITION BY Tag ORDER BY InfluenceScore DESC NULLS LAST) AS ContributorRank,
         dense_rank() OVER (ORDER BY TotalQuestionsTagged DESC) AS TagPopularityRank,
         ntile(10) OVER (ORDER BY InfluenceScore DESC NULLS LAST) AS InfluenceDecile
  FROM BenchmarkPrep
)
SELECT
  r.Tag,
  r.TagPopularityRank,
  r.TotalQuestionsTagged,
  r.HotQuestionsLastYear,
  r.LinkedOutCount,
  r.DuplicateCount,
  r.DistinctTopContributors,
  r.ContributorRank,
  r.TopUserId,
  r.TopUserName,
  r.TopUserRep,
  r.GoldBadges,
  r.SilverBadges,
  r.BronzeBadges,
  r.QuestionsAsked,
  r.AnswersPosted,
  r.CommentsMade,
  r.UpVotesCast,
  r.DownVotesCast,
  round(r.AvgAnswerScore3y::numeric,3) AS AvgAnswerScore3y,
  r.MostUsedTag AS TopUserMostUsedTag,
  r.AnswersLastYear,
  r.AnswersLast3Years,
  r.FirstAnswerAt,
  r.LastAnswerAt,
  round(r.InfluenceScore::numeric,4) AS InfluenceScore,
  r.InfluenceDecile
FROM RankedResults r
WHERE r.ContributorRank <= 10
  AND r.TotalQuestionsTagged >= 100
ORDER BY r.TagPopularityRank, r.InfluenceScore DESC
LIMIT 1000;