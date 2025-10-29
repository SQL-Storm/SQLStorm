-- {"query": "1393.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2589} 
WITH QuestionBase AS (
    -- Base information for all questions (PostTypeId = 1)
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        COALESCE(u.DisplayName, p.OwnerDisplayName, 'Community User') AS OwnerName,
        u.Reputation AS OwnerReputation,
        u.CreationDate AS UserCreationDate,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        p.Body,
        p.Title,
        COALESCE(p.ClosedDate, '9999-12-31 23:59:59') AS EffectiveClosedDate, -- Sentinel value for non-closed posts
        (EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600.0) AS HoursActiveSinceCreation,
        CASE
            WHEN LOWER(p.Title) LIKE '%sql%' OR LOWER(p.Body) LIKE '%database%' OR LOWER(p.Tags) LIKE '%<sql>%' THEN TRUE
            ELSE FALSE
        END AS ContainsRelevantTechKeyword
    FROM Posts AS p
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
PostAggregatedActivity AS (
    -- Aggregate comments and edits for each post
    SELECT
        qb.PostId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS UserComments,
        AVG(COALESCE(c.Score, 0)) AS AvgCommentScore,
        COUNT(ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryCount,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS LastEditDate,
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS DistinctEditors
    FROM QuestionBase AS qb
    LEFT JOIN Comments AS c ON qb.PostId = c.PostId
    LEFT JOIN PostHistory AS ph ON qb.PostId = ph.PostId
    GROUP BY qb.PostId
),
QuestionVoteSummary AS (
    -- Summarize vote activity for questions
    SELECT
        qb.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes -- User-bookmarked (legacy/different meaning now)
    FROM QuestionBase AS qb
    LEFT JOIN Votes AS v ON qb.PostId = v.PostId
    GROUP BY qb.PostId
),
TagAnalysis AS (
    -- Explode tags for each question
    SELECT
        qb.PostId,
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(qb.Tags, 2, LENGTH(qb.Tags) - 2), '><'))) AS TagName
    FROM QuestionBase AS qb
    WHERE qb.Tags IS NOT NULL AND LENGTH(qb.Tags) > 2
),
TagAggregates AS (
    -- Aggregate tag information per question
    SELECT
        ta.PostId,
        STRING_AGG(ta.TagName, ', ' ORDER BY ta.TagName) AS AllTags,
        COUNT(ta.TagName) AS TagCount,
        SUM(t.Count) AS TotalTagPopularityScore, -- Sum of global counts for tags on this post
        MAX(t.IsModeratorOnly) AS HasModeratorOnlyTag,
        MAX(t.IsRequired) AS HasRequiredTag
    FROM TagAnalysis AS ta
    LEFT JOIN Tags AS t ON ta.TagName = t.TagName
    GROUP BY ta.PostId
),
PostLinkSummary AS (
    -- Summarize linked and duplicated posts
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateOfCount,
        COUNT(DISTINCT pl.RelatedPostId) AS DistinctRelatedPosts
    FROM PostLinks AS pl
    GROUP BY pl.PostId
)
-- Main query combining all CTEs and applying complex logic
SELECT
    qb.PostId,
    qb.Title,
    qb.OwnerName,
    qb.OwnerReputation,
    qb.CreationDate,
    qb.LastActivityDate,
    qb.Score AS QuestionScore,
    qb.ViewCount,
    qb.AnswerCount,
    qb.CommentCount AS QuestionBaseCommentCount, -- From Posts table
    qb.FavoriteCount AS QuestionBaseFavoriteCount, -- From Posts table
    COALESCE(aa.TotalComments, 0) AS TotalCommentsAggregated, -- From PostAggregatedActivity
    COALESCE(aa.UserComments, 0) AS UserCommentsAggregated,
    COALESCE(aa.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(aa.EditCount, 0) AS EditCount,
    COALESCE(aa.DistinctEditors, 0) AS DistinctEditors,
    COALESCE(aa.CloseHistoryCount, 0) AS CloseHistoryCount,
    qb.EffectiveClosedDate AS ClosedDate,
    COALESCE(qvs.UpVotes, 0) AS UpVotes,
    COALESCE(qvs.DownVotes, 0) AS DownVotes,
    COALESCE(qvs.AcceptedAnswerVotes, 0) AS AcceptedAnswerVotes,
    COALESCE(qvs.FavoriteVotes, 0) AS FavoriteVotesAggregated,
    COALESCE(pls.LinkedFromCount, 0) AS LinkedPosts,
    COALESCE(pls.DuplicateOfCount, 0) AS DuplicatedByPosts,
    COALESCE(pls.DistinctRelatedPosts, 0) AS TotalRelatedPosts,
    COALESCE(tag_agg.TagCount, 0) AS NumberOfTags,
    COALESCE(tag_agg.AllTags, '[no tags]') AS QuestionTagsList,
    COALESCE(tag_agg.TotalTagPopularityScore, 0) AS CombinedTagPopularity,
    COALESCE(tag_agg.HasModeratorOnlyTag, FALSE) AS HasModeratorOnlyTag,
    COALESCE(tag_agg.HasRequiredTag, FALSE) AS HasRequiredTag,
    qb.ContainsRelevantTechKeyword,
    qb.HoursActiveSinceCreation,
    (qb.Score * 0.4 + COALESCE(qb.AnswerCount, 0) * 0.3 + COALESCE(aa.TotalComments, 0) * 0.2 + COALESCE(qvs.UpVotes, 0) * 0.1) AS WeightedActivityScore,
    RANK() OVER (ORDER BY (qb.Score + qb.ViewCount + COALESCE(qvs.UpVotes, 0)) DESC, qb.CreationDate ASC) AS GlobalActivityRank,
    NTILE(5) OVER (ORDER BY (qb.Score + qb.ViewCount + COALESCE(qvs.UpVotes, 0)) DESC) AS TopActivityQuintile,
    -- Correlated subquery to find the most recent closing reason, if any
    (SELECT crt.Name
     FROM PostHistory ph_corr
     JOIN CloseReasonTypes crt ON ph_corr.Comment::smallint = crt.Id -- Explicit cast for comment which holds CloseReasonId
     WHERE ph_corr.PostId = qb.PostId
       AND ph_corr.PostHistoryTypeId = 10 -- Post Closed
     ORDER BY ph_corr.CreationDate DESC
     LIMIT 1
    ) AS MostRecentCloseReason,
    -- Another correlated subquery to check if owner has a specific badge
    EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = qb.OwnerUserId AND b.Name = 'Popular Question' AND b.Class = 2 AND b.Date >= qb.CreationDate) AS HasPopularQuestionBadge,
    CASE
        WHEN qb.EffectiveClosedDate < '9999-12-31 23:59:59' AND (EXTRACT(EPOCH FROM (qb.EffectiveClosedDate - qb.CreationDate)) / 86400.0) < 7 THEN 'Quickly Closed'
        WHEN COALESCE(qb.AnswerCount, 0) = 0 AND COALESCE(aa.TotalComments, 0) = 0 AND qb.LastActivityDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' THEN 'Stale No Engagement'
        WHEN qb.OwnerReputation > 10000 AND COALESCE(aa.EditCount, 0) > 5 AND COALESCE(pls.LinkedFromCount, 0) > 0 THEN 'Highly Managed & Referenced'
        WHEN qb.ContainsRelevantTechKeyword AND COALESCE(qb.AnswerCount, 0) > 3 AND COALESCE(qb.Score, 0) > 20 THEN 'High-Value Tech Question'
        WHEN qb.OwnerUserId IS NOT NULL AND qb.UserCreationDate IS NOT NULL AND (qb.CreationDate - qb.UserCreationDate) < INTERVAL '30 days' THEN 'New User Question'
        ELSE 'Regular Activity'
    END AS QuestionCategory,
    -- NULL logic for view count and score combined metric
    COALESCE(qb.ViewCount / NULLIF(qb.Score, 0), 0.0) AS ViewScoreRatio
FROM QuestionBase AS qb
LEFT JOIN PostAggregatedActivity AS aa ON qb.PostId = aa.PostId
LEFT JOIN QuestionVoteSummary AS qvs ON qb.PostId = qvs.PostId
LEFT JOIN PostLinkSummary AS pls ON qb.PostId = pls.PostId
LEFT JOIN TagAggregates AS tag_agg ON qb.PostId = tag_agg.PostId
WHERE qb.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years' -- Limit to recent questions for performance
  AND qb.OwnerUserId IS NOT NULL
  AND (qb.ViewCount > 100 OR qb.Score > 5 OR COALESCE(aa.TotalComments, 0) > 5) -- Filter for more active/visible questions
  AND (NOT qb.ContainsRelevantTechKeyword OR qb.HoursActiveSinceCreation > 24 OR COALESCE(tag_agg.HasRequiredTag, FALSE)) -- Example of a complex predicate with multiple conditions
ORDER BY WeightedActivityScore DESC, qb.CreationDate DESC
LIMIT 1000;