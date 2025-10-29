-- {"query": "1002.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2504}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY u.Reputation) AS ReputationDecile,
        CAST(u.UpVotes AS NUMERIC) / NULLIF(u.DownVotes, 0) AS UpDownVoteRatio,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS MostRecentPostDate,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)) / 86400.0 AS DaysSinceLastAccess
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.Title,
        p.Tags,
        (p.Score * 2 + COALESCE(p.ViewCount, 0) / 100.0 + COALESCE(p.AnswerCount, 0) * 3 + COALESCE(p.CommentCount, 0) * 1.5 + COALESCE(p.FavoriteCount, 0) * 5) AS PopularityScore,
        TRIM(BOTH '>' FROM REPLACE(REPLACE(p.Tags, '>', ','), '<', '')) AS FormattedTags,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered & Accepted'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Open'
        END AS QuestionStatus,
        (SELECT ph.UserDisplayName
         FROM PostHistory ph
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
         ORDER BY ph.CreationDate DESC
         LIMIT 1) AS LastEditorDisplayNameFromHistory,
        (SELECT COUNT(DISTINCT UserId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS DistinctEditors
    FROM Posts p
    WHERE p.PostTypeId = 1
),
PostHistoryAggregates AS (
    -- compute per-post edit intervals first, then aggregate
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS DistinctContributorsToHistory,
        MIN(ph.CreationDate) AS FirstHistoryEvent,
        MAX(ph.CreationDate) AS LastHistoryEvent,
        (SELECT crt.Name
         FROM PostHistory ph_close
         JOIN CloseReasonTypes crt ON CAST(ph_close.Comment AS INTEGER) = crt.Id
         WHERE ph_close.PostId = ph.PostId
           AND ph_close.PostHistoryTypeId = 10
         ORDER BY ph_close.CreationDate DESC
         LIMIT 1) AS LastCloseReason,
        -- average difference computed by deriving lead differences in a subquery
        AVG(ph_diff.SecondsBetween) / 86400.0 AS AvgDaysBetweenEdits
    FROM PostHistory ph
    LEFT JOIN (
        -- for each history row compute seconds until next event for same post
        SELECT
            ph2.Id,
            ph2.PostId,
            EXTRACT(EPOCH FROM (LEAD(ph2.CreationDate) OVER (PARTITION BY ph2.PostId ORDER BY ph2.CreationDate) - ph2.CreationDate)) AS SecondsBetween
        FROM PostHistory ph2
    ) ph_diff ON ph.Id = ph_diff.Id
    GROUP BY ph.PostId
),
AnswerQuality AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        COALESCE(SUM(a.Score), 0) AS TotalAnswerScore,
        COALESCE(AVG(a.Score), 0.0) AS AverageAnswerScore,
        (SELECT p_acc.Score FROM Posts p_acc WHERE p_acc.Id = q.AcceptedAnswerId) AS AcceptedAnswerScore,
        (SELECT u_acc.Reputation FROM Posts p_acc JOIN Users u_acc ON p_acc.OwnerUserId = u_acc.Id WHERE p_acc.Id = q.AcceptedAnswerId) AS AcceptedAnswerOwnerReputation
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.AcceptedAnswerId
)
SELECT
    pd.PostId,
    pd.Title,
    ue.DisplayName AS QuestionOwnerDisplayName,
    ue.Reputation AS QuestionOwnerReputation,
    ue.ReputationRank AS QuestionOwnerReputationRank,
    ue.ReputationDecile AS QuestionOwnerReputationDecile,
    ue.TotalBadges AS QuestionOwnerBadges,
    pd.PostCreationDate,
    pd.PostScore,
    pd.ViewCount,
    pd.AnswerCount,
    aq.TotalAnswers,
    aq.AverageAnswerScore,
    aq.AcceptedAnswerScore,
    aq.AcceptedAnswerOwnerReputation,
    pd.PopularityScore,
    pd.QuestionStatus,
    pd.FormattedTags,
    ph_agg.EditCount AS TotalEditsToQuestion,
    ph_agg.DistinctContributorsToHistory,
    ph_agg.AvgDaysBetweenEdits,
    ph_agg.LastCloseReason,
    pd.LastEditorDisplayNameFromHistory,
    pd.DistinctEditors,
    (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = pd.PostId) AS TotalUpVotesFromVotesTable,
    CASE
        WHEN pd.AnswerCount > 5 AND pd.PostScore > 100 AND pd.ViewCount > 10000 THEN 'Highly Engaged & Popular'
        WHEN pd.PostScore > 50 AND ph_agg.EditCount > 5 THEN 'Well-Maintained & Valued'
        WHEN pd.ClosedDate IS NOT NULL AND ph_agg.LastCloseReason LIKE '%Duplicate%' THEN 'Closed as Duplicate'
        ELSE 'Standard Activity'
    END AS QuestionEngagementCategory,
    RANK() OVER (PARTITION BY ue.ReputationDecile ORDER BY pd.PopularityScore DESC) AS RankWithinOwnerRepDecile,
    COALESCE(ue.DisplayName, 'Community User') AS EffectiveOwner,
    CASE
        WHEN pd.PostCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
             AND pd.ViewCount > 5000
             AND ph_agg.LastHistoryEvent > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
        THEN 'Evergreen Question'
        ELSE 'Normal'
    END AS LifecycleStage
FROM PostDetails pd
LEFT JOIN UserEngagement ue ON pd.OwnerUserId = ue.UserId
LEFT JOIN PostHistoryAggregates ph_agg ON pd.PostId = ph_agg.PostId
LEFT JOIN AnswerQuality aq ON pd.PostId = aq.QuestionId
WHERE pd.PostScore > 5
  AND ue.Reputation > 100
  AND (
        (aq.TotalAnswers > 0 AND COALESCE(aq.AcceptedAnswerScore, 0) > 10)
        OR (pd.ViewCount > 5000 AND pd.FavoriteCount > 10 AND ue.HasGoldBadge = 1)
      )
  AND (
        (pd.FormattedTags LIKE '%sql%' OR pd.FormattedTags LIKE '%database%' OR pd.FormattedTags LIKE '%performance%')
        OR (pd.LastEditDate IS NOT NULL AND pd.LastEditorDisplayNameFromHistory IS NOT NULL)
      )
ORDER BY pd.PopularityScore DESC, ue.Reputation DESC
LIMIT 100;