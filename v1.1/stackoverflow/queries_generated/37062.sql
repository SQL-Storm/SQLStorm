-- {"query": "37062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2150} 
WITH
-- 1) Select recent active questions with rich aggregates
RecentQuestions AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount,
         ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '730 days') -- last 2 years
    AND p.AnswerCount >= 1
),

-- 2) Top answer per question by score (ties broken by CreationDate)
TopAnswers AS (
  SELECT a.ParentId AS QuestionId,
         a.Id AS AnswerId,
         a.OwnerUserId AS AnswerOwnerId,
         a.Score AS AnswerScore,
         a.CreationDate AS AnswerCreationDate,
         a.Body AS AnswerBody,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.ParentId IS NOT NULL
),

TopAnswersFiltered AS (
  SELECT * FROM TopAnswers WHERE rn = 1
),

-- 3) Aggregate votes distribution for posts (up/down/accept/favorites)
PostVoteAgg AS (
  SELECT v.PostId,
         SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedCount,
         SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteCount
  FROM Votes v
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY v.PostId
),

-- 4) Author statistics: badges, reputation trajectory (first/last activity), posting rates
AuthorStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate AS UserCreated,
         u.LastAccessDate,
         COALESCE(bad.badge_count,0) AS BadgeCount,
         COALESCE(bad.gold,0) AS GoldBadges,
         COALESCE(bad.silver,0) AS SilverBadges,
         COALESCE(bad.bronze,0) AS BronzeBadges,
         COALESCE(post_counts.posts,0) AS TotalPosts,
         COALESCE(ans_counts.answers,0) AS TotalAnswers,
         COALESCE(q_counts.questions,0) AS TotalQuestions
  FROM Users u
  LEFT JOIN (
    SELECT UserId,
           COUNT(*) AS badge_count,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
    FROM Badges
    GROUP BY UserId
  ) bad ON bad.UserId = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS uid, COUNT(*) AS posts
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ) post_counts ON post_counts.uid = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS uid, COUNT(*) AS answers
    FROM Posts
    WHERE PostTypeId = 2 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ) ans_counts ON ans_counts.uid = u.Id
  LEFT JOIN (
    SELECT OwnerUserId AS uid, COUNT(*) AS questions
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ) q_counts ON q_counts.uid = u.Id
),

-- 5) Tag exploded table (one row per tag per question) for tag-level analytics
QuestionTags AS (
  SELECT q.Id AS QuestionId,
         trim(tag) AS Tag
  FROM Posts q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) AS tag
  ) t
  WHERE q.PostTypeId = 1
    AND q.Tags IS NOT NULL
),

-- 6) Recent edits and closures from PostHistory (flaggers / close reasons)
PostEdits AS (
  SELECT ph.PostId,
         ph.PostHistoryTypeId,
         pht.Name AS HistoryType,
         ph.UserId AS EditorUserId,
         ph.CreationDate AS EditDate,
         ph.Comment,
         ph.Text AS RevisionText
  FROM PostHistory ph
  LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
  WHERE ph.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '365 days')
    AND ph.PostHistoryTypeId IN (4,5,6,10,11,12,13,14,15,19,20,24,52)
),

-- 7) Linked posts graph metrics (outgoing/incoming links, duplicates)
PostLinkAgg AS (
  SELECT pl.PostId,
         SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS OutgoingLinks,
         SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateMarked,
         COUNT(*) AS TotalLinks
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),

-- 8) Heavy-weight per-question summary combining the pieces
QuestionSummary AS (
  SELECT rq.QuestionId,
         rq.Title,
         rq.OwnerUserId,
         rq.CreationDate AS QuestionCreated,
         rq.Score AS QuestionScore,
         rq.ViewCount,
         rq.AnswerCount,
         rq.CommentCount,
         rq.FavoriteCount,
         qt.Tag,
         pva.UpVotes   AS QuestionUpVotes,
         pva.DownVotes AS QuestionDownVotes,
         pva.AcceptedCount AS QuestionAcceptedCount,
         pa.AnswerId,
         pa.AnswerOwnerId,
         pa.AnswerScore,
         pa.AnswerCreationDate,
         pva_a.UpVotes   AS AnswerUpVotes,
         pva_a.DownVotes AS AnswerDownVotes,
         la.OutgoingLinks,
         la.DuplicateMarked,
         ea.EditDate AS LastEditDate,
         ea.HistoryType AS LastEditType,
         au.DisplayName AS AuthorName,
         au.Reputation AS AuthorReputation,
         au.BadgeCount AS AuthorBadgeCount,
         au.GoldBadges,
         au.SilverBadges,
         au.BronzeBadges,
         COALESCE(tag_stats.tag_popularity,0) AS TagPopularity -- number of questions with this tag
  FROM RecentQuestions rq
  LEFT JOIN QuestionTags qt ON qt.QuestionId = rq.QuestionId
  LEFT JOIN PostVoteAgg pva ON pva.PostId = rq.QuestionId
  LEFT JOIN TopAnswersFiltered pa ON pa.QuestionId = rq.QuestionId
  LEFT JOIN PostVoteAgg pva_a ON pva_a.PostId = pa.AnswerId
  LEFT JOIN PostLinkAgg la ON la.PostId = rq.QuestionId
  LEFT JOIN LATERAL (
    SELECT ph2.PostId, ph2.CreationDate, pht2.Name
    FROM PostHistory ph2
    LEFT JOIN PostHistoryTypes pht2 ON ph2.PostHistoryTypeId = pht2.Id
    WHERE ph2.PostId = rq.QuestionId
    ORDER BY ph2.CreationDate DESC
    LIMIT 1
  ) ea ON TRUE
  LEFT JOIN AuthorStats au ON au.UserId = rq.OwnerUserId
  LEFT JOIN (
    SELECT Tag, COUNT(*) AS tag_popularity
    FROM QuestionTags
    GROUP BY Tag
  ) tag_stats ON tag_stats.Tag = qt.Tag
  WHERE rq.rn <= 1000 -- limit to the most recent 1000 questions for performance control
)

-- Final selection: wide analytic projection with windowed metrics, percentile ranks, and simulated heavy text ops
SELECT qs.*,
       -- Per-question percentiles among the window
       PERCENT_RANK() OVER (PARTITION BY qs.Tag ORDER BY qs.QuestionScore) AS ScorePctInTag,
       NTILE(10) OVER (ORDER BY qs.QuestionScore DESC) AS ScoreDecileOverall,
       -- Correlation-like metric: z-score of answer score within tag
       (qs.AnswerScore - AVG(qs.AnswerScore) OVER (PARTITION BY qs.Tag)) /
         NULLIF(STDDEV(qs.AnswerScore) OVER (PARTITION BY qs.Tag),0) AS AnswerScoreZByTag,
       -- Textual complexity heuristics (simulated heavy ops): length and approximate sentence count
       length(coalesce(qs.AnswerBody,'')) AS AnswerBodyLength,
       (length(coalesce(qs.AnswerBody,'')) - length(replace(coalesce(qs.AnswerBody,''),'.',''))) AS ApproxSentenceCount,
       -- Composite hotness score (weighted)
       (COALESCE(qs.QuestionScore,0) * 1.5 +
        COALESCE(qs.ViewCount,0) * 0.001 +
        COALESCE(qs.AnswerScore,0) * 2.0 +
        COALESCE(qs.QuestionUpVotes,0) * 1.2 -
        COALESCE(qs.QuestionDownVotes,0) * 1.5 +
        COALESCE(qs.DuplicateMarked,0) * -5 +
        COALESCE(qs.OutgoingLinks,0) * 0.5 +
        COALESCE(qs.AuthorReputation,0) * 0.0005
       ) AS HotnessScore
FROM QuestionSummary qs
ORDER BY HotnessScore DESC, qs.QuestionCreated DESC
LIMIT 500;