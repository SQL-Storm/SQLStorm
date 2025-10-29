-- {"query": "1238.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3353}
WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE
        u.Id IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostActivityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        COALESCE(p.Score, 0) AS CurrentScore,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.LastEditDate,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.OwnerUserId,
        p.Tags,
        (SELECT COUNT(DISTINCT ph_inner.UserId)
         FROM PostHistory ph_inner
         WHERE ph_inner.PostId = p.Id
           AND ph_inner.PostHistoryTypeId IN (4, 5, 6, 8)
           AND ph_inner.UserId IS NOT NULL
        ) AS DistinctEditorCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosedPost,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.LastActivityDate)) / 86400 AS DaysSinceLastActivity,
        (LOWER(p.Title) LIKE '%performance%' OR LOWER(p.Title) LIKE '%optimization%' OR LOWER(p.Title) LIKE '%benchmark%') AS IsPerformanceRelated
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2)
),
TagPopularity AS (
    SELECT
        tag_name AS tag_name,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.LastActivityDate) AS LastActivityDateForTag
    FROM
        Posts p,
        unnest(string_to_array(
            substring(p.Tags FROM 2 FOR CASE WHEN char_length(p.Tags) - 2 < 0 THEN 0 ELSE char_length(p.Tags) - 2 END),
            '><'
        )) AS tag_name
    WHERE
        p.PostTypeId = 1
        AND p.Tags IS NOT NULL
        AND p.Tags != ''
    GROUP BY
        tag_name
),
RecentPostHistoryActivity AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS RecentEditEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 ELSE NULL END) AS RecentCloseReopenEvents,
        COUNT(DISTINCT ph.UserId) AS UniqueHistoryUsers,
        MAX(ph.CreationDate) AS LastHistoryDate,
        MIN(ph.CreationDate) AS FirstHistoryDate,
        EXISTS (
            SELECT 1
            FROM PostHistory ph_inner
            JOIN Users u_inner ON ph_inner.UserId = u_inner.Id
            WHERE ph_inner.PostId = ph.PostId
              AND u_inner.Reputation > 20000
              AND ph_inner.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
        ) AS HasHighRepUserHistoryRecent
    FROM
        PostHistory ph
    WHERE
        ph.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
        AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY
        ph.PostId
),
CombinedPostFeatures AS (
    SELECT
        pam.PostId,
        pam.PostTypeId,
        pam.Title,
        pam.CurrentScore,
        pam.ViewCount,
        pam.AnswerCount,
        pam.CommentCount,
        pam.DaysSinceLastActivity,
        pam.DistinctEditorCount,
        pam.IsClosedPost,
        pam.HasAcceptedAnswer,
        pam.OwnerUserId,
        COALESCE(rpha.RecentEditEvents, 0) AS RecentEditEvents,
        COALESCE(rpha.RecentCloseReopenEvents, 0) AS RecentCloseReopenEvents,
        COALESCE(rpha.UniqueHistoryUsers, 0) AS UniqueHistoryUsers,
        COALESCE(rpha.HasHighRepUserHistoryRecent, FALSE) AS HasHighRepUserHistoryRecent,
        pam.IsPerformanceRelated,
        (pam.CurrentScore * 0.5) +
        (pam.ViewCount / 100.0 * 0.2) +
        (pam.AnswerCount * 1.5) +
        (pam.CommentCount * 0.8) +
        (CASE WHEN pam.HasAcceptedAnswer THEN 5 ELSE 0 END) +
        (COALESCE(rpha.RecentEditEvents, 0) * 2.0) +
        (COALESCE(rpha.RecentCloseReopenEvents, 0) * 3.0) +
        (CASE WHEN pam.DaysSinceLastActivity < 7 THEN 10 ELSE 0 END) +
        (CASE WHEN pam.IsPerformanceRelated THEN 7 ELSE 0 END) +
        (CASE WHEN COALESCE(rpha.HasHighRepUserHistoryRecent, FALSE) THEN 15 ELSE 0 END) +
        (pam.DistinctEditorCount * 0.7)
        AS PostHotnessScore
    FROM
        PostActivityMetrics pam
    LEFT JOIN RecentPostHistoryActivity rpha ON pam.PostId = rpha.PostId
    WHERE
        pam.DaysSinceLastActivity < 365
        AND pam.ViewCount > 50
        AND pam.PostTypeId = 1
),
RankedPostsAndUsers AS (
    SELECT
        cpf.PostId,
        cpf.PostTypeId,
        cpf.Title,
        cpf.CurrentScore,
        cpf.ViewCount,
        cpf.AnswerCount,
        cpf.CommentCount,
        cpf.DaysSinceLastActivity,
        cpf.IsClosedPost,
        cpf.HasAcceptedAnswer,
        cpf.RecentEditEvents,
        cpf.RecentCloseReopenEvents,
        cpf.UniqueHistoryUsers,
        cpf.HasHighRepUserHistoryRecent,
        cpf.IsPerformanceRelated,
        cpf.PostHotnessScore,
        ues.UserId AS OwnerUserId,
        ues.DisplayName AS OwnerDisplayName,
        ues.Reputation AS OwnerReputation,
        ues.TotalPosts AS OwnerTotalPosts,
        ues.TotalAnswers AS OwnerTotalAnswers,
        ues.TotalComments AS OwnerTotalComments,
        (CAST(ues.TotalUpvotesReceived AS NUMERIC) / NULLIF(ues.TotalUpvotesReceived + ues.TotalDownvotesReceived, 0)) AS OwnerUpvoteRatio,
        RANK() OVER (ORDER BY cpf.PostHotnessScore DESC, cpf.DaysSinceLastActivity ASC) AS PostHotnessRank,
        NTILE(10) OVER (ORDER BY ues.Reputation DESC, ues.TotalPosts DESC) AS UserEngagementTier
    FROM
        CombinedPostFeatures cpf
    LEFT JOIN UserEngagementSummary ues ON cpf.OwnerUserId = ues.UserId
    WHERE
        ues.Reputation > 1000
        AND cpf.PostHotnessScore > 20
),
TopTagsPerRankedPost AS (
    SELECT
        rp.PostId,
        COALESCE(ranked_tags.TagName, 'untagged_or_unknown') AS MostPopularTagForPost
    FROM
        RankedPostsAndUsers rp
    LEFT JOIN LATERAL (
        SELECT tp.tag_name AS TagName
        FROM Posts p_inner
        JOIN unnest(string_to_array(
            substring(p_inner.Tags FROM 2 FOR CASE WHEN char_length(p_inner.Tags) - 2 < 0 THEN 0 ELSE char_length(p_inner.Tags) - 2 END),
            '><'
        )) AS post_tag ON TRUE
        JOIN TagPopularity tp ON post_tag = tp.tag_name
        WHERE p_inner.Id = rp.PostId
        ORDER BY tp.QuestionCount DESC, tp.AvgQuestionScore DESC
        LIMIT 1
    ) AS ranked_tags ON TRUE
)
SELECT
    rpu.PostId,
    rpu.PostTypeId,
    rpu.Title,
    rpu.CurrentScore,
    rpu.ViewCount,
    rpu.AnswerCount,
    rpu.CommentCount,
    rpu.DaysSinceLastActivity,
    rpu.IsClosedPost,
    rpu.HasAcceptedAnswer,
    rpu.RecentEditEvents,
    rpu.RecentCloseReopenEvents,
    rpu.UniqueHistoryUsers,
    rpu.HasHighRepUserHistoryRecent,
    rpu.IsPerformanceRelated,
    rpu.PostHotnessScore,
    rpu.PostHotnessRank,
    rpu.OwnerUserId,
    COALESCE(rpu.OwnerDisplayName, 'Deleted User') AS OwnerDisplayName,
    rpu.OwnerReputation,
    rpu.OwnerTotalPosts,
    rpu.OwnerTotalAnswers,
    rpu.OwnerTotalComments,
    COALESCE(rpu.OwnerUpvoteRatio, 0.0) AS OwnerUpvoteRatio,
    rpu.UserEngagementTier,
    ttprp.MostPopularTagForPost,
    UPPER(SUBSTRING(CAST(ttprp.MostPopularTagForPost AS varchar) FROM 1 FOR 3)) || '-' || LPAD(CAST(rpu.PostId AS varchar), 8, '0') AS PostCode_Identifier,
    CASE
        WHEN rpu.IsClosedPost AND rpu.RecentCloseReopenEvents > 0 AND rpu.OwnerReputation < 5000 THEN 'Volatile_Closed_LowRepOwner'
        WHEN rpu.PostHotnessRank <= 10 AND rpu.UserEngagementTier = 1 THEN 'Top_Tier_Hot_Post_And_User'
        WHEN rpu.DaysSinceLastActivity < 30 AND COALESCE(rpu.OwnerUpvoteRatio, 0.0) > 0.8 THEN 'Fresh_HighlyRated_ByOwner'
        WHEN rpu.IsPerformanceRelated AND rpu.PostHotnessRank <= 50 THEN 'HighImpact_PerformanceTopic'
        ELSE 'General_Active_Content'
    END AS PostCategory,
    EXISTS (
        SELECT 1
        FROM PostLinks pl_inner
        WHERE (pl_inner.PostId = rpu.PostId OR pl_inner.RelatedPostId = rpu.PostId)
          AND pl_inner.LinkTypeId = 3
    ) AS HasDuplicateLinks
FROM
    RankedPostsAndUsers rpu
JOIN TopTagsPerRankedPost ttprp ON rpu.PostId = ttprp.PostId
WHERE
    rpu.PostHotnessRank <= 100
    AND rpu.UserEngagementTier IN (1, 2, 3)
ORDER BY
    rpu.PostHotnessRank ASC, rpu.OwnerReputation DESC, ttprp.MostPopularTagForPost ASC;