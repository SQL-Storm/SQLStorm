WITH
RecentAnswers AS (
  SELECT p.Id AS AnswerId, p.ParentId AS QuestionId, p.OwnerUserId, p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 2
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
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
         tag AS Tag
  FROM RecentAnswers a
  JOIN QuestionTags qt ON qt.QuestionId = a.QuestionId,
  LATERAL (
    SELECT value AS tag
    FROM (
      SELECT TRIM(t) AS value
      FROM (
        SELECT regexp_split_to_table(st.stripped, '><') AS t
        FROM (
          SELECT regexp_replace(qt.Tags, '^<|>$', '') AS stripped
        ) st
      ) sub1
    ) sub2
  ) tags
),
TagUserStats AS (
  SELECT Tag, OwnerUserId AS UserId,
         count(CASE WHEN CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN 1 END) AS AnswersLastYear,
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
         coalesce(avg(a.Score) FILTER (WHERE a.PostTypeId=2 AND a.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')),0) AS AvgAnswerScore3y,
         tag_top.MostUsedTag
  FROM Users u
  LEFT JOIN (
    SELECT UserId,
           sum(CASE WHEN Class=1 THEN 1 ELSE 0 END) AS BadgeGold,
           sum(CASE WHEN Class=2 THEN 1 ELSE 0 END) AS BadgeSilver,
           sum(CASE WHEN Class=3 THEN 1 ELSE 0 END) AS BadgeBronze
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
           sum(CASE WHEN VoteTypeId=2 THEN 1 ELSE 0 END) AS UpVotes,
           sum(CASE WHEN VoteTypeId=3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId,
           (array_agg(tag ORDER BY cnt DESC))[1] AS MostUsedTag
    FROM (
      SELECT p.OwnerUserId,
             tag,
             count(*) AS cnt
      FROM Posts p,
      LATERAL (
        SELECT value AS tag
        FROM (
          SELECT TRIM(t) AS value
          FROM (
            SELECT regexp_split_to_table(st.stripped, '><') AS t
            FROM (
              SELECT regexp_replace(p.Tags, '^<|>$', '') AS stripped
            ) st
          ) sub1
        ) sub2
      ) tags
      WHERE p.PostTypeId = 2 AND p.Tags IS NOT NULL
      GROUP BY p.OwnerUserId, tag
    ) s
    GROUP BY OwnerUserId
  ) tag_top ON tag_top.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
           b.BadgeGold, b.BadgeSilver, b.BadgeBronze,
           pq.QuestionsAsked, pa.AnswersPosted, pc.TotalComments, v.UpVotes, v.DownVotes, tag_top.MostUsedTag
),
TagSummary AS (
  SELECT t.TagName AS Tag,
         t.Count AS TotalQuestionsTagged,
         coalesce(qHot.HotQuestions,0) AS HotQuestionsLastYear,
         coalesce(links.LinkedOut,0) AS LinkedOutCount,
         coalesce(links.Duplicates,0) AS DuplicateCount,
         coalesce(topcontributors.TopContribCount,0) AS DistinctTopContributors
  FROM Tags t
  LEFT JOIN (
    SELECT tag AS Tag, count(*) AS HotQuestions
    FROM (
      SELECT p.Id,
             (SELECT value FROM (
                SELECT TRIM(t) AS value
                FROM (
                  SELECT regexp_split_to_table(st.stripped, '><') AS t
                  FROM (
                    SELECT regexp_replace(p.Tags, '^<|>$', '') AS stripped
                  ) st
                ) sub1
              ) sub2 LIMIT 1) AS tag
      FROM Posts p
      WHERE p.PostTypeId = 1
        AND p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        AND p.ViewCount > 10000
    ) sub
    GROUP BY tag
  ) qHot ON qHot.Tag = t.TagName
  LEFT JOIN (
    SELECT tag AS Tag,
           sum(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedOut,
           sum(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS Duplicates
    FROM PostLinks pl
    JOIN Posts p ON p.Id = pl.PostId,
    LATERAL (
      SELECT value AS tag
      FROM (
        SELECT TRIM(t) AS value
        FROM (
          SELECT regexp_split_to_table(st.stripped, '><') AS t
          FROM (
            SELECT regexp_replace(p.Tags, '^<|>$', '') AS stripped
          ) st
        ) sub1
      ) sub2
    ) tags
    WHERE p.PostTypeId = 1
    GROUP BY tag
  ) links ON links.Tag = t.TagName
  LEFT JOIN (
    SELECT Tag, count(DISTINCT UserId) AS TopContribCount
    FROM TopTagContributors
    GROUP BY Tag
  ) topcontributors ON topcontributors.Tag = t.TagName
),
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
  SELECT ts.Tag,
         ts.TotalQuestionsTagged,
         ts.HotQuestionsLastYear,
         ts.LinkedOutCount,
         ts.DuplicateCount,
         ts.DistinctTopContributors,
         ts.TopUserId,
         ts.TopUserName,
         ts.TopUserRep,
         ts.GoldBadges,
         ts.SilverBadges,
         ts.BronzeBadges,
         ts.QuestionsAsked,
         ts.AnswersPosted,
         ts.CommentsMade,
         ts.UpVotesCast,
         ts.DownVotesCast,
         ts.AvgAnswerScore3y,
         ts.MostUsedTag,
         ts.AnswersLastYear,
         ts.AnswersLast3Years,
         ts.FirstAnswerAt,
         ts.LastAnswerAt,
         ts.InfluenceScore,
         rank() OVER (PARTITION BY ts.Tag ORDER BY ts.InfluenceScore DESC NULLS LAST) AS ContributorRank,
         dense_rank() OVER (ORDER BY ts.TotalQuestionsTagged DESC) AS TagPopularityRank,
         ntile(10) OVER (ORDER BY ts.InfluenceScore DESC NULLS LAST) AS InfluenceDecile
  FROM BenchmarkPrep ts
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
  round(CAST(r.AvgAnswerScore3y AS numeric),3) AS AvgAnswerScore3y,
  r.MostUsedTag AS TopUserMostUsedTag,
  r.AnswersLastYear,
  r.AnswersLast3Years,
  r.FirstAnswerAt,
  r.LastAnswerAt,
  round(CAST(r.InfluenceScore AS numeric),4) AS InfluenceScore,
  r.InfluenceDecile
FROM RankedResults r
WHERE r.ContributorRank <= 10
  AND r.TotalQuestionsTagged >= 100
ORDER BY r.TagPopularityRank, r.InfluenceScore DESC
LIMIT 1000;