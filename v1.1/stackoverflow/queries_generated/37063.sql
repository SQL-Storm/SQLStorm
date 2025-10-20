-- {"query": "37063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2301} 
WITH
-- recent active questions with tag arrays and parsed tags
Questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
         COALESCE(p.AnswerCount,0) AS AnswerCount,
         COALESCE(p.CommentCount,0) AS CommentCount,
         COALESCE(p.FavoriteCount,0) AS FavoriteCount,
         -- split tags like '<sql><performance>' into array ['sql','performance']
         CASE WHEN p.Tags IS NULL THEN ARRAY[]::text[]
              ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')
         END AS TagList
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '3 years'
),
-- top answer per question by score, tie-breaker recent
TopAnswers AS (
  SELECT a.ParentId AS QuestionId, a.Id AS AnswerId, a.OwnerUserId AS AnswerOwnerId,
         a.Score AS AnswerScore, a.CreationDate AS AnswerCreationDate,
         a.CommentCount AS AnswerCommentCount
  FROM Posts a
  JOIN (
    SELECT ParentId, max((Score::bigint<<32) + extract(epoch from CreationDate)::bigint) AS keyval
    FROM Posts
    WHERE PostTypeId = 2 AND CreationDate >= now() - interval '3 years'
    GROUP BY ParentId
  ) best ON a.ParentId = best.ParentId
  WHERE a.PostTypeId = 2
    AND ((a.Score::bigint<<32) + extract(epoch from a.CreationDate)::bigint) =
        (SELECT max((x.Score::bigint<<32) + extract(epoch from x.CreationDate)::bigint) FROM Posts x WHERE x.ParentId = a.ParentId AND x.PostTypeId=2)
),
-- aggregate votes for posts in window
PostVoteAgg AS (
  SELECT v.PostId,
         count(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
         count(*) FILTER (WHERE v.VoteTypeId = 8) AS BountyStarts,
         min(v.CreationDate) AS FirstVoteDate,
         max(v.CreationDate) AS LastVoteDate
  FROM Votes v
  WHERE v.CreationDate >= now() - interval '3 years'
  GROUP BY v.PostId
),
-- recent activity from PostHistory: edits, close/reopen, migrated, bumps
PostHistoryAgg AS (
  SELECT ph.PostId,
         count(*) FILTER (WHERE ph.PostHistoryTypeId IN (2,5,8,24)) AS EditCount,
         count(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13)) AS CloseReopenCount,
         max(ph.CreationDate) AS LastHistoryDate
  FROM PostHistory ph
  WHERE ph.CreationDate >= now() - interval '3 years'
  GROUP BY ph.PostId
),
-- user aggregates: reputation, badges, activity
UserAgg AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate AS UserCreation,
         u.Views AS ProfileViews,
         COALESCE(bc.Gold,0) AS GoldBadges,
         COALESCE(bc.Silver,0) AS SilverBadges,
         COALESCE(bc.Bronze,0) AS BronzeBadges,
         COALESCE(qs.QuestionCount,0) AS QuestionsPosted,
         COALESCE(ans.AnswerCount,0) AS AnswersPosted,
         COALESCE(com.CommentCount,0) AS CommentsMade
  FROM Users u
  LEFT JOIN (
    SELECT UserId,
           sum(case when Class=1 then 1 else 0 end) AS Gold,
           sum(case when Class=2 then 1 else 0 end) AS Silver,
           sum(case when Class=3 then 1 else 0 end) AS Bronze
    FROM Badges
    GROUP BY UserId
  ) bc ON bc.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, count(*) AS QuestionCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
  ) qs ON qs.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId, count(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
  ) ans ON ans.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, count(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
  ) com ON com.UserId = u.Id
),
-- compute tag popularity over window: number of questions, avg score, avg views
TagAgg AS (
  SELECT tag AS TagName,
         count(*) AS QuestionCount,
         avg(q.Score) AS AvgScore,
         avg(q.ViewCount) AS AvgViews,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY q.Score) AS MedianScore
  FROM Questions q,
       unnest(q.TagList) AS tag
  GROUP BY tag
  HAVING count(*) >= 10
),
-- join everything to produce heavy analytical result per question
QuestionAnalytics AS (
  SELECT q.Id AS QuestionId, q.Title, q.CreationDate AS QuestionCreation,
         q.Score AS QuestionScore, q.ViewCount, q.AnswerCount, q.CommentCount,
         q.FavoriteCount, q.TagList,
         ta.TagName AS PrimaryTag, ta.QuestionCount AS TagQuestionCount,
         ta.AvgScore AS TagAvgScore, ta.AvgViews AS TagAvgViews,
         pa.UpVotes, pa.DownVotes, pa.Favorites, pa.BountyStarts,
         pha.EditCount, pha.CloseReopenCount, pha.LastHistoryDate,
         twn.AnswerId AS TopAnswerId, twn.AnswerScore, twn.AnswerCreationDate, twn.AnswerOwnerId,
         u.Reputation AS OwnerReputation, u.QuestionsPosted, u.AnswersPosted, u.GoldBadges, u.SilverBadges, u.BronzeBadges,
         -- derived metrics
         (q.Score::decimal / GREATEST(NULLIF(q.ViewCount,0),1)) AS ScorePerView,
         (COALESCE(pa.UpVotes,0) - COALESCE(pa.DownVotes,0))::decimal / GREATEST(NULLIF(q.ViewCount,0),1) AS NetVotesPerView,
         (COALESCE(twn.AnswerScore,0) - q.Score) AS AnswerScoreDelta,
         (COALESCE(pa.Favorites,0)::decimal / GREATEST(q.AnswerCount,1)) AS FavoritesPerAnswer,
         (CASE WHEN ta.QuestionCount > 0 THEN (q.Score::decimal / ta.AvgScore) ELSE NULL END) AS ScoreRelativeToTagAvg
  FROM Questions q
  LEFT JOIN LATERAL (
    SELECT unnest(q.TagList) AS Tag, row_number() OVER () rn
  ) tags ON true
  LEFT JOIN TagAgg ta ON ta.TagName = tags.Tag AND tags.rn = 1
  LEFT JOIN PostVoteAgg pa ON pa.PostId = q.Id
  LEFT JOIN PostHistoryAgg pha ON pha.PostId = q.Id
  LEFT JOIN TopAnswers twn ON twn.QuestionId = q.Id
  LEFT JOIN UserAgg u ON u.UserId = q.OwnerUserId
  WHERE ta.TagName IS NOT NULL
)
-- final selection: heavy aggregation, ranking, window functions and json construction to stress planner
SELECT
  qa.QuestionId,
  qa.Title,
  qa.PrimaryTag,
  qa.TagQuestionCount,
  qa.QuestionCreation,
  qa.QuestionScore,
  qa.ViewCount,
  qa.AnswerCount,
  qa.TopAnswerId,
  qa.AnswerScore,
  qa.OwnerReputation,
  qa.GoldBadges,
  qa.SilverBadges,
  qa.BronzeBadges,
  qa.EditCount,
  qa.CloseReopenCount,
  qa.UpVotes,
  qa.DownVotes,
  qa.Favorites,
  qa.ScorePerView,
  qa.NetVotesPerView,
  qa.AnswerScoreDelta,
  qa.FavoritesPerAnswer,
  qa.ScoreRelativeToTagAvg,
  -- rank by a composite engagement metric
  rank() OVER (PARTITION BY qa.PrimaryTag ORDER BY (qa.ViewCount * 0.4 + qa.QuestionScore * 10 + COALESCE(qa.UpVotes,0) * 5 + COALESCE(qa.Favorites,0) * 8 + qa.AnswerCount * 7) DESC) AS TagRank,
  dense_rank() OVER (ORDER BY (qa.ViewCount * 0.3 + qa.QuestionScore * 8 + COALESCE(qa.UpVotes,0) * 4) DESC) AS GlobalEngagementRank,
  -- moving averages within tag over time (3-month and 12-month windows)
  avg(qa.QuestionScore) OVER (PARTITION BY qa.PrimaryTag ORDER BY qa.QuestionCreation RANGE BETWEEN INTERVAL '90 days' PRECEDING AND CURRENT ROW) AS AvgScore_3mo,
  avg(qa.QuestionScore) OVER (PARTITION BY qa.PrimaryTag ORDER BY qa.QuestionCreation RANGE BETWEEN INTERVAL '365 days' PRECEDING AND CURRENT ROW) AS AvgScore_12mo,
  -- top co-occurring tags for this question's primary tag
  (SELECT json_agg(obj) FROM (
     SELECT other.TagName, other.QuestionCount, other.AvgScore
     FROM TagAgg other
     WHERE other.TagName <> qa.PrimaryTag
       AND EXISTS (
         SELECT 1 FROM Questions q2
         WHERE qa.PrimaryTag = ANY(q2.TagList) AND other.TagName = ANY(q2.TagList)
         AND q2.CreationDate >= now() - interval '3 years'
       )
     ORDER BY other.QuestionCount DESC
     LIMIT 5
  ) obj) AS TopCooccurringTags,
  -- sample recent commenters (up to 3) with counts
  (SELECT json_agg(cobj) FROM (
     SELECT c.UserId, u.DisplayName, count(*) AS CommentsOnQuestion
     FROM Comments c
     LEFT JOIN Users u ON u.Id = c.UserId
     WHERE c.PostId = qa.QuestionId
     GROUP BY c.UserId, u.DisplayName
     ORDER BY CommentsOnQuestion DESC
     LIMIT 3
  ) cobj) AS TopCommenters
FROM QuestionAnalytics qa
WHERE qa.QuestionCreation >= now() - interval '3 years'
  AND qa.TagQuestionCount >= 10
ORDER BY GlobalEngagementRank
LIMIT 200;