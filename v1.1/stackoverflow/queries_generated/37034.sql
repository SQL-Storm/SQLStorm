-- {"query": "37034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1872} 
WITH
-- recent active questions with tag arrays and basic aggregates
questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
         coalesce(p.Tags, '') AS TagsRaw,
         -- split tags of form '<tag1><tag2>' into array elements
         CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
              ELSE string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
         END AS Tags,
         p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > now() - interval '5 years'
    AND p.Score IS NOT NULL
),
-- top answer stats per question
answer_stats AS (
  SELECT parent.Id AS QuestionId,
         count(a.Id) FILTER (WHERE a.Score >= 0) AS PosAnswerCount,
         count(a.Id) FILTER (WHERE a.Score < 0) AS NegAnswerCount,
         max(a.Score) AS MaxAnswerScore,
         avg(a.Score)::numeric(10,3) AS AvgAnswerScore,
         sum(case when a.OwnerUserId IS NULL then 0 else 1 end) AS AnsweredByRegisteredUsers
  FROM Posts a
  JOIN Posts parent ON a.ParentId = parent.Id
  WHERE a.PostTypeId = 2
  GROUP BY parent.Id
),
-- compute hotness score combining views, score, answers, age decay, and tag rarity
tag_rarity AS (
  SELECT t.TagName, greatest(log(100000.0 / NULLIF(t.Count,0)), 0) AS RarityScore
  FROM Tags t
),
question_tag_stats AS (
  SELECT q.Id AS QuestionId,
         array_agg(distinct tr.TagName) FILTER (WHERE tr.TagName IS NOT NULL) AS TagList,
         coalesce(sum(tr.RarityScore),0)::numeric(10,3) AS TagRaritySum,
         coalesce(max(tr.RarityScore),0)::numeric(10,3) AS TagRarityMax,
         count(distinct tr.TagName) AS TagCount
  FROM questions q
  LEFT JOIN unnest(q.Tags) AS tg(tag) ON true
  LEFT JOIN tag_rarity tr ON tr.TagName = tg.tag
  GROUP BY q.Id
),
-- recent activity: last comment, last edit, last answer times
recent_activity AS (
  SELECT q.Id AS QuestionId,
         max(c.CreationDate) AS LastCommentAt,
         max(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS LastEditAt,
         max(a.CreationDate) FILTER (WHERE a.PostTypeId = 2) AS LastAnswerAt
  FROM questions q
  LEFT JOIN Comments c ON c.PostId = q.Id
  LEFT JOIN PostHistory ph ON ph.PostId = q.Id
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  GROUP BY q.Id
),
-- user reputation and badge-weighted influence
user_influence AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         coalesce(sum(b.Class = 1)::int,0) AS GoldCount,
         coalesce(sum(b.Class = 2)::int,0) AS SilverCount,
         coalesce(sum(b.Class = 3)::int,0) AS BronzeCount,
         -- influence metric: reputation plus badges with weights
         (u.Reputation * 0.01 + coalesce(sum(
            CASE b.Class WHEN 1 THEN 50 WHEN 2 THEN 10 WHEN 3 THEN 2 ELSE 0 END
         ),0))::numeric(12,3) AS InfluenceScore
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation
),
-- votes aggregation for question and its answers
vote_agg AS (
  SELECT p.Id AS PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) AS UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) AS DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) AS Favorites
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
  GROUP BY p.Id
),
-- compute final composite hotness and engagement score
composite AS (
  SELECT q.*,
         qs.TagCount, qs.TagRaritySum, qs.TagRarityMax, qs.TagList,
         coalesce(a.PosAnswerCount,0) AS PosAnswerCount,
         coalesce(a.NegAnswerCount,0) AS NegAnswerCount,
         coalesce(a.MaxAnswerScore,0) AS MaxAnswerScore,
         coalesce(a.AvgAnswerScore,0) AS AvgAnswerScore,
         ra.LastCommentAt, ra.LastEditAt, ra.LastAnswerAt,
         coalesce(vq.UpVotes,0) AS QuestionUpVotes,
         coalesce(vq.DownVotes,0) AS QuestionDownVotes,
         coalesce(vq.Favorites,0) AS QuestionFavorites,
         ui.InfluenceScore AS OwnerInfluence,
         -- age in days
         greatest(extract(epoch from (now() - q.CreationDate)) / 86400.0, 0)::numeric(12,6) AS AgeDays,
         -- time decay factor: recent => closer to 1, older => smaller
         (1 / (1 + greatest(extract(epoch from (now() - q.CreationDate)) / 86400.0,1) / 30))::numeric(12,6) AS AgeDecay
  FROM questions q
  LEFT JOIN question_tag_stats qs ON qs.QuestionId = q.Id
  LEFT JOIN answer_stats a ON a.QuestionId = q.Id
  LEFT JOIN recent_activity ra ON ra.QuestionId = q.Id
  LEFT JOIN vote_agg vq ON vq.PostId = q.Id
  LEFT JOIN user_influence ui ON ui.UserId = q.OwnerUserId
)
SELECT
  c.Id AS QuestionId,
  c.Title,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.TagList,
  c.TagCount,
  c.TagRaritySum,
  c.PosAnswerCount,
  c.NegAnswerCount,
  c.MaxAnswerScore,
  c.AvgAnswerScore,
  c.LastCommentAt,
  c.LastEditAt,
  c.LastAnswerAt,
  c.QuestionUpVotes,
  c.QuestionDownVotes,
  c.QuestionFavorites,
  c.OwnerInfluence,
  c.AgeDays,
  -- compute engagement: views * (upvotes - downvotes + favorites*2) scaled by answers and owner influence
  ( (c.ViewCount::numeric + greatest(c.Score,0)::numeric * 50)
    * (greater(c.QuestionUpVotes - c.QuestionDownVotes, 0)::numeric + 1)
    * (1 + least(c.PosAnswerCount::numeric, 10) / 10)
    * (1 + c.OwnerInfluence / 1000)
    * c.AgeDecay
    + c.TagRaritySum * 100
  )::numeric(18,3) AS EngagementScore,
  -- compute novelty: favors rare tags and low-view high-score questions
  ( (c.TagRaritySum * 10)
    + (greatest(0, c.Score)::numeric * 20)
    - log(1 + c.ViewCount::numeric)::numeric * 5
    + (1 / (1 + c.AgeDays)) * 100
  )::numeric(12,3) AS NoveltyScore,
  -- final composite for ranking: weighted combination
  (
    ( ( (c.ViewCount::numeric / NULLIF(GREATEST((SELECT avg(ViewCount) FROM Posts WHERE PostTypeId=1),1),0)) * 0.25 )
      + (c.Score::numeric / NULLIF(GREATEST((SELECT avg(Score) FROM Posts WHERE PostTypeId=1),1),0) * 0.25)
      + (c.EngagementScore::numeric / NULLIF(GREATEST( (SELECT avg(( (ViewCount::numeric + greatest(Score,0)::numeric * 50) * (1+1) * 1) FROM Posts WHERE PostTypeId=1),1),0) ,1) * 0.35)
      + (c.NoveltyScore::numeric * 0.15)
    )
  )::numeric(18,6) AS CompositeRankScore
FROM composite c
ORDER BY CompositeRankScore DESC
LIMIT 250;