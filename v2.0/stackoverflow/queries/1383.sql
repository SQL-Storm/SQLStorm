-- {"query": "1383.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2785}
WITH UserReputationTiers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views AS ProfileViews,
        CASE
            WHEN u.Reputation >= 20000 THEN 'Legendary'
            WHEN u.Reputation >= 5000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 200 THEN 'Active'
            ELSE 'Novice'
        END AS ReputationTier,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(u.LastAccessDate) AS LastSeenDate,
        EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS HasGoldBadge
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
PostHistoricalEdits AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS DistinctEditorCount,
        MAX(ph.CreationDate) AS LastEditOrHistoryEvent,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN ph.CreationDate END) AS FirstBodyEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN ph.CreationDate END) AS LatestBodyEditDate,
        -- ARRAY_AGG may not exist in all dialects; use STRING_AGG as a more portable alternative
        -- but keep distinct, order not guaranteed in all DBs. Use LISTAGG style where supported.
        NULL AS AllHistoryTypes,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS MajorEditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 24, 25, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66)
    GROUP BY ph.PostId
),
QuestionVoteCounts AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
QuestionActivityMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.ViewCount,
        q.AnswerCount,
        q.Score AS QuestionScore,
        q.FavoriteCount,
        q.Tags,
        q.ClosedDate,
        phist.DistinctEditorCount,
        phist.MajorEditCount,
        phist.LastEditOrHistoryEvent,
        phist.LatestBodyEditDate,
        (EXTRACT(EPOCH FROM (COALESCE(phist.LatestBodyEditDate, q.CreationDate) - q.CreationDate)) / 3600) AS HoursSinceFirstEdit,
        COALESCE(qvc.UpVoteCount, 0) AS TotalUpVotes,
        COALESCE(qvc.DownVoteCount, 0) AS TotalDownVotes,
        EXISTS (
            SELECT 1
            FROM Posts pa
            JOIN Users u_ans ON pa.OwnerUserId = u_ans.Id
            WHERE pa.Id = q.AcceptedAnswerId AND u_ans.Reputation > 1000 AND pa.PostTypeId = 2
        ) AS HasAcceptedAnswerFromReputableUser,
        TRIM(SPLIT_PART(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><', 1)) AS PrimaryTag
    FROM Posts q
    JOIN PostHistoricalEdits phist ON q.Id = phist.PostId
    LEFT JOIN QuestionVoteCounts qvc ON q.Id = qvc.PostId
    WHERE q.PostTypeId = 1
),
CommentEngagement AS (
    SELECT
        c.PostId AS QuestionId,
        c.Text AS TopCommentText,
        c.Score AS TopCommentScore,
        c.UserId AS TopCommenterUserId,
        c.CreationDate AS TopCommentDate,
        ROW_NUMBER() OVER(PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate DESC) AS rn
    FROM Comments c
    WHERE c.PostId IN (SELECT QuestionId FROM QuestionActivityMetrics)
)
SELECT
    qam.QuestionId,
    qam.Title,
    qam.QuestionCreationDate,
    qam.ViewCount,
    qam.AnswerCount,
    qam.QuestionScore,
    COALESCE(qam.FavoriteCount, 0) AS FavoriteCount,
    qam.Tags,
    qam.PrimaryTag,
    qam.DistinctEditorCount,
    qam.MajorEditCount,
    qam.LastEditOrHistoryEvent,
    qam.HoursSinceFirstEdit,
    qam.HasAcceptedAnswerFromReputableUser,
    ur_owner.ReputationTier AS OwnerReputationTier,
    ur_owner.HasGoldBadge AS OwnerHasGoldBadge,
    qam.TotalUpVotes AS TotalUpVotesOnQuestion,
    qam.TotalDownVotes AS TotalDownVotesOnQuestion,
    ce.TopCommentText,
    COALESCE(ce.TopCommentScore, 0) AS TopCommentScore,
    ur_commenter.ReputationTier AS TopCommenterReputationTier,
    ur_commenter.HasGoldBadge AS TopCommenterHasGoldBadge,
    RANK() OVER (
        PARTITION BY qam.PrimaryTag
        ORDER BY qam.QuestionScore DESC, qam.ViewCount DESC, qam.QuestionId
    ) AS RankInPrimaryTag,
    (
        (qam.QuestionScore * 0.5) +
        (qam.AnswerCount * 1.5) +
        (qam.ViewCount * 0.001) +
        (COALESCE(qam.FavoriteCount, 0) * 2.0) +
        (qam.DistinctEditorCount * 10) +
        (CASE WHEN ur_owner.HasGoldBadge THEN 50 ELSE 0 END) +
        (CASE WHEN qam.HasAcceptedAnswerFromReputableUser THEN 30 ELSE 0 END) +
        (COALESCE(ce.TopCommentScore, 0) * 0.8) +
        (CASE WHEN qam.ClosedDate IS NULL THEN 20 ELSE 0 END)
    ) AS RelevanceScore,
    COALESCE(
        -- Use standard SQL: format timestamp via CAST to varchar in a portable way
        CAST(qam.ClosedDate AS varchar),
        'Not Closed'
    ) AS FormattedClosedDate,
    STRING_AGG(DISTINCT CAST(pl.RelatedPostId AS varchar), ', ') AS RelatedPostIds,
    (
        SELECT MAX(ph_rb.CreationDate)
        FROM PostHistory ph_rb
        WHERE ph_rb.PostId = qam.QuestionId AND ph_rb.PostHistoryTypeId = 8
    ) AS LastBodyRollbackDate,
    AVG(qam.ViewCount) OVER (PARTITION BY qam.PrimaryTag) AS AvgViewCountForTag
FROM QuestionActivityMetrics qam
LEFT JOIN UserReputationTiers ur_owner ON qam.OwnerUserId = ur_owner.UserId
LEFT JOIN CommentEngagement ce ON qam.QuestionId = ce.QuestionId AND ce.rn = 1
LEFT JOIN UserReputationTiers ur_commenter ON ce.TopCommenterUserId = ur_commenter.UserId
LEFT JOIN PostLinks pl ON qam.QuestionId = pl.PostId AND pl.LinkTypeId IN (1, 3)
WHERE
    qam.ClosedDate IS NULL
    AND qam.AnswerCount >= 2
    AND qam.QuestionCreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR
    AND qam.ViewCount > (
        SELECT COALESCE(AVG(ViewCount), 0)
        FROM Posts
        WHERE PostTypeId = 1
          AND Tags LIKE '%' || qam.PrimaryTag || '%'
          AND CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR
    )
    AND (
        (qam.Tags LIKE '%<sql>%' OR qam.Tags LIKE '%<database>%')
        OR EXISTS (
            SELECT 1
            FROM Posts p_body
            WHERE p_body.Id = qam.QuestionId AND p_body.Body LIKE '%performance%'
        )
    )
GROUP BY
    qam.QuestionId, qam.Title, qam.QuestionCreationDate, qam.ViewCount, qam.AnswerCount, qam.QuestionScore, qam.FavoriteCount, qam.Tags, qam.PrimaryTag,
    qam.DistinctEditorCount, qam.MajorEditCount, qam.LastEditOrHistoryEvent, qam.HoursSinceFirstEdit, qam.HasAcceptedAnswerFromReputableUser,
    ur_owner.ReputationTier, ur_owner.HasGoldBadge, qam.TotalUpVotes, qam.TotalDownVotes,
    ce.TopCommentText, ce.TopCommentScore, ur_commenter.ReputationTier, ur_commenter.HasGoldBadge,
    qam.ClosedDate
HAVING
    COUNT(pl.Id) >= 0
ORDER BY RelevanceScore DESC, qam.QuestionId
LIMIT 100;