-- {"query": "37017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1772} 
WITH
-- recent active questions with tag counts and engagement metrics
RecentQuestions AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.FavoriteCount,
    q.Tags,
    COALESCE(array_length(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><'),1),0) AS TagCount
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= now() - interval '365 days'
),
-- aggregate answers per question with top answer and answerer stats
AnswerAgg AS (
  SELECT
    a.ParentId AS QuestionId,
    count(*) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS AnswersWithOwners,
    count(*) AS TotalAnswers,
    max(a.Score) AS MaxAnswerScore,
    avg(a.Score) AS AvgAnswerScore,
    -- pick the highest-scored answer id (ties -> newest)
    (SELECT aa.Id FROM Posts aa WHERE aa.ParentId = a.ParentId AND aa.PostTypeId = 2 ORDER BY aa.Score DESC, aa.CreationDate DESC LIMIT 1) AS TopAnswerId,
    (SELECT u.Id FROM Posts aa JOIN Users u ON aa.OwnerUserId = u.Id WHERE aa.ParentId = a.ParentId AND aa.PostTypeId = 2 ORDER BY aa.Score DESC, aa.CreationDate DESC LIMIT 1) AS TopAnswererId
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.CreationDate >= now() - interval '365 days'
  GROUP BY a.ParentId
),
-- recent comments per question (including comments on answers)
CommentAgg AS (
  SELECT
    p.Id AS QuestionId,
    count(c.Id) FILTER (WHERE c.CreationDate >= now() - interval '90 days') AS RecentComments90,
    count(c.Id) AS TotalComments
  FROM Posts p
  LEFT JOIN Comments c
    ON (c.PostId = p.Id OR c.PostId IN (SELECT id FROM Posts WHERE ParentId = p.Id))
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
-- votes summary per post (limited to last year for activity)
VoteAgg AS (
  SELECT
    v.PostId,
    sum(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
    sum(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
    sum(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites,
    count(*) AS TotalVotes
  FROM Votes v
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate >= now() - interval '365 days'
  GROUP BY v.PostId
),
-- tag-level popularity: explode tags and aggregate per tag
ExplodedTags AS (
  SELECT
    r.QuestionId,
    trim(both '<>' from tag) AS Tag
  FROM RecentQuestions r,
  unnest(string_to_array(substring(r.Tags,2,length(r.Tags)-2), '><')) AS tag
),
TagStats AS (
  SELECT
    et.Tag,
    count(DISTINCT et.QuestionId) AS QuestionsInYear,
    sum(r.ViewCount) AS TotalViews,
    avg(r.Score) AS AvgQuestionScore,
    max(r.ViewCount) AS MaxViewOnQuestion
  FROM ExplodedTags et
  JOIN RecentQuestions r ON r.QuestionId = et.QuestionId
  GROUP BY et.Tag
),
-- user reputation and badge enrichment for top answerers and askers
UserBadges AS (
  SELECT
    b.UserId,
    count(*) FILTER (WHERE b.Class = 1) AS Gold,
    count(*) FILTER (WHERE b.Class = 2) AS Silver,
    count(*) FILTER (WHERE b.Class = 3) AS Bronze,
    count(*) FILTER (WHERE b.TagBased = B'1') AS TagBadges
  FROM Badges b
  GROUP BY b.UserId
),
UserSummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(ub.Gold,0) AS Gold,
    COALESCE(ub.Silver,0) AS Silver,
    COALESCE(ub.Bronze,0) AS Bronze,
    COALESCE(ub.TagBadges,0) AS TagBadges,
    u.Views,
    u.UpVotes,
    u.DownVotes
  FROM Users u
  LEFT JOIN UserBadges ub ON ub.UserId = u.Id
),
-- identify duplicate link relationships (questions marked duplicate or linked)
DuplicateLinks AS (
  SELECT
    pl.PostId AS FromQuestion,
    pl.RelatedPostId AS ToQuestion,
    lt.Name AS LinkType,
    pfrom.Title AS FromTitle,
    pto.Title AS ToTitle
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  JOIN Posts pfrom ON pfrom.Id = pl.PostId
  JOIN Posts pto ON pto.Id = pl.RelatedPostId
  WHERE pfrom.PostTypeId = 1 AND pto.PostTypeId = 1
),
-- assemble final ranked set for benchmarking with window functions and joins
RankedQuestions AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.AnswerCount,
    r.FavoriteCount,
    r.TagCount,
    COALESCE(va.UpVotes,0) AS UpVotesLastYear,
    COALESCE(va.DownVotes,0) AS DownVotesLastYear,
    COALESCE(aa.TotalAnswers,0) AS TotalAnswersLastYear,
    COALESCE(aa.MaxAnswerScore,0) AS MaxAnswerScoreLastYear,
    COALESCE(ca.RecentComments90,0) AS RecentComments90,
    COALESCE(ts.TagsTop,'') AS TopTags,
    -- composite engagement score (complex calculation to stress engine)
    ( (r.ViewCount::numeric * 0.1)
      + (r.Score * 4)
      + (COALESCE(va.UpVotes,0) * 3)
      - (COALESCE(va.DownVotes,0) * 2)
      + (COALESCE(aa.TotalAnswers,0) * 10)
      + (COALESCE(aa.MaxAnswerScore,0) * 5)
      + (COALESCE(ca.RecentComments90,0) * 2)
      + (COALESCE(r.FavoriteCount,0) * 8)
    ) AS EngagementScore
  FROM RecentQuestions r
  LEFT JOIN VoteAgg va ON va.PostId = r.QuestionId
  LEFT JOIN AnswerAgg aa ON aa.QuestionId = r.QuestionId
  LEFT JOIN CommentAgg ca ON ca.QuestionId = r.QuestionId
  LEFT JOIN (
    SELECT
      et.QuestionId,
      string_agg(ts.Tag || ':Q' || ts.QuestionsInYear :: text || ':V' || ts.TotalViews :: text, '; ' ORDER BY ts.QuestionsInYear DESC NULLS LAST) AS TagsTop
    FROM ExplodedTags et
    JOIN TagStats ts ON ts.Tag = trim(et.Tag)
    GROUP BY et.QuestionId
  ) ts ON ts.QuestionId = r.QuestionId
)
SELECT
  rq.QuestionId,
  rq.Title,
  rq.CreationDate,
  rq.TagCount,
  rq.TopTags,
  rq.ViewCount,
  rq.Score,
  rq.AnswerCount,
  rq.TotalAnswersLastYear,
  rq.UpVotesLastYear,
  rq.DownVotesLastYear,
  rq.RecentComments90,
  rq.EngagementScore,
  ROW_NUMBER() OVER (ORDER BY rq.EngagementScore DESC) AS EngagementRank,
  RANK() OVER (PARTITION BY rq.TagCount ORDER BY rq.EngagementScore DESC) AS RankWithinTagCount,
  PERCENT_RANK() OVER (ORDER BY rq.EngagementScore) AS EngagementPercentile
FROM RankedQuestions rq
WHERE rq.EngagementScore IS NOT NULL
ORDER BY rq.EngagementScore DESC
LIMIT 250;