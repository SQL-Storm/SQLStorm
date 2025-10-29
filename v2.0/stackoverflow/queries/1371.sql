WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(p.ViewCount, 0)) AS AvgPostViewCount,
        MAX(p.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentActivity,
        DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate) AS UserAccountAgeDays,
        AVG(SUM(COALESCE(p.Score, 0))) OVER (ORDER BY u.CreationDate ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS MovingAvgUserPostScore
    FROM
        Users AS u
    LEFT JOIN
        Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments AS c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.UpVotes, u.DownVotes
),
PostHistoryMetrics AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS EditOrRollbackCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        MAX(ph.CreationDate) AS LatestHistoryEventDate,
        (
            SELECT u2.DisplayName
            FROM PostHistory AS ph2
            JOIN Users AS u2 ON ph2.UserId = u2.Id
            WHERE ph2.PostId = ph.PostId
              AND ph2.PostHistoryTypeId IN (4, 5, 6, 8, 9)
            ORDER BY ph2.CreationDate DESC
            LIMIT 1
        ) AS LastEditorDisplayNameFromHistory,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '101' THEN 1 ELSE 0 END) AS HasBeenClosedAsDuplicate
    FROM
        PostHistory AS ph
    GROUP BY
        ph.PostId
),
TagUsageStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        COUNT(DISTINCT tag_name.value) AS DistinctTagsPerPost,
        STRING_AGG(tag_name.value, ';') AS AllTagsConcatenated,
        MAX(CASE WHEN POSITION('<performance>' IN p.Tags) > 0 THEN 1 ELSE 0 END) AS HasPerformanceTag,
        MAX(CASE WHEN POSITION('<sql>' IN p.Tags) > 0 THEN 1 ELSE 0 END) AS HasSqlTag,
        MAX(CASE WHEN p.Tags LIKE '%<database>%' THEN 1 ELSE 0 END) AS HasDatabaseTag,
        MAX(CASE WHEN p.Tags LIKE '%<javascript>%' AND POSITION('<node.js>' IN p.Tags) = 0 THEN 1 ELSE 0 END) AS HasJavascriptButNoNodejsTag
    FROM
        Posts AS p
    LEFT JOIN (
        SELECT
            p2.Id AS parent_post_id,
            UNNEST(string_to_array(SUBSTRING(p2.Tags FROM 2 FOR LENGTH(p2.Tags) - 2), '><')) AS value
        FROM Posts p2
        WHERE p2.Tags IS NOT NULL
    ) AS tag_name ON tag_name.parent_post_id = p.Id
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
    GROUP BY
        p.Id, p.PostTypeId
),
BadgeAwards AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Badges AS b
    GROUP BY
        b.UserId
),
BasePostAnalysis AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.UserAccountAgeDays,
        ue.TotalPosts,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.TotalPostScore,
        ue.AvgPostViewCount,
        ue.MovingAvgUserPostScore,
        ba.TotalBadges,
        ba.GoldBadges,
        ba.SilverBadges,
        ba.BronzeBadges,
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate AS PostLastActivityDate,
        p.LastEditDate,
        p.FavoriteCount,
        phm.TotalHistoryEvents,
        phm.EditOrRollbackCount,
        phm.CloseEventCount,
        phm.LatestHistoryEventDate,
        phm.LastEditorDisplayNameFromHistory,
        phm.HasBeenClosedAsDuplicate,
        tus.DistinctTagsPerPost,
        tus.AllTagsConcatenated,
        tus.HasPerformanceTag,
        tus.HasSqlTag,
        tus.HasDatabaseTag,
        tus.HasJavascriptButNoNodejsTag,
        (p.Score * 0.5 + p.ViewCount * 0.01 + COALESCE(p.FavoriteCount, 0) * 1.0 + COALESCE(p.AnswerCount, 0) * 2.0) AS PostValueScore,
        COALESCE(DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - p.LastEditDate), -1) AS DaysSinceLastEdit,
        SUBSTRING(REPLACE(REPLACE(COALESCE(p.Body, 'No content.'), '<p>', ''), '</p>', ' '), 1, 100) AS BodyExcerpt,
        (SELECT COUNT(b2.Id) FROM Badges AS b2 WHERE b2.UserId = ue.UserId AND b2.Class = 1 AND b2.TagBased = FALSE) > 0 AS OwnerHasNamedGoldBadge,
        CASE
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL AND (SELECT q.AcceptedAnswerId FROM Posts q WHERE q.Id = p.ParentId) IS NOT NULL
            THEN 'Parent Accepted Answer'
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL
            THEN 'Parent No Accepted Answer'
            ELSE 'Not an Answer'
        END AS ParentQuestionStatus
    FROM
        UserEngagement AS ue
    LEFT JOIN
        BadgeAwards AS ba ON ue.UserId = ba.UserId
    JOIN
        Posts AS p ON ue.UserId = p.OwnerUserId
    LEFT JOIN
        PostHistoryMetrics AS phm ON p.Id = phm.PostId
    LEFT JOIN
        TagUsageStats AS tus ON p.Id = tus.PostId
    WHERE
        p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
        AND p.OwnerUserId IS NOT NULL
        AND ue.TotalPosts > (SELECT AVG(TotalPosts) FROM UserEngagement)
)
SELECT
    bpa.UserId,
    bpa.DisplayName,
    bpa.Reputation,
    bpa.PostId,
    bpa.PostTypeId,
    'High_Impact_Question' AS AnalysisType,
    bpa.Title,
    bpa.PostScore,
    bpa.PostViewCount,
    bpa.AnswerCount,
    bpa.PostCreationDate,
    bpa.PostLastActivityDate,
    bpa.TotalHistoryEvents,
    bpa.EditOrRollbackCount,
    bpa.CloseEventCount,
    bpa.LastEditorDisplayNameFromHistory,
    bpa.HasBeenClosedAsDuplicate,
    bpa.DistinctTagsPerPost,
    bpa.AllTagsConcatenated,
    bpa.HasPerformanceTag,
    bpa.HasSqlTag,
    bpa.HasDatabaseTag,
    bpa.HasJavascriptButNoNodejsTag,
    bpa.PostValueScore,
    bpa.DaysSinceLastEdit,
    bpa.BodyExcerpt,
    bpa.OwnerHasNamedGoldBadge,
    bpa.ParentQuestionStatus,
    ROW_NUMBER() OVER (PARTITION BY bpa.DisplayName ORDER BY bpa.PostScore DESC, bpa.PostCreationDate DESC) AS PostRankByScore,
    (bpa.PostScore * bpa.AnswerCount * COALESCE(bpa.FavoriteCount, 0)) / (NULLIF(bpa.PostViewCount, 0) + 1.0) AS QuestionEngagementIndex,
    NULL AS AnswerQualityMetric,
    CASE
        WHEN bpa.PostScore > 100 AND bpa.AnswerCount > 5 THEN 'Viral Question'
        WHEN bpa.CloseEventCount > 0 AND bpa.HasBeenClosedAsDuplicate = 1 THEN 'Duplicate Question'
        ELSE 'Standard Question'
    END AS QuestionCategory
FROM
    BasePostAnalysis AS bpa
WHERE
    bpa.PostTypeId = 1
    AND bpa.PostScore >= 50
    AND bpa.AnswerCount >= 2
    AND (bpa.HasPerformanceTag = 1 OR bpa.HasSqlTag = 1 OR bpa.HasDatabaseTag = 1)
    AND bpa.HasBeenClosedAsDuplicate = 0
    AND bpa.PostLastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
UNION ALL
SELECT
    bpa.UserId,
    bpa.DisplayName,
    bpa.Reputation,
    bpa.PostId,
    bpa.PostTypeId,
    'High_Edit_Answer' AS AnalysisType,
    bpa.Title,
    bpa.PostScore,
    bpa.PostViewCount,
    bpa.AnswerCount,
    bpa.PostCreationDate,
    bpa.PostLastActivityDate,
    bpa.TotalHistoryEvents,
    bpa.EditOrRollbackCount,
    bpa.CloseEventCount,
    bpa.LastEditorDisplayNameFromHistory,
    bpa.HasBeenClosedAsDuplicate,
    NULL AS DistinctTagsPerPost,
    NULL AS AllTagsConcatenated,
    0 AS HasPerformanceTag,
    0 AS HasSqlTag,
    0 AS HasDatabaseTag,
    0 AS HasJavascriptButNoNodejsTag,
    bpa.PostValueScore,
    bpa.DaysSinceLastEdit,
    bpa.BodyExcerpt,
    bpa.OwnerHasNamedGoldBadge,
    bpa.ParentQuestionStatus,
    ROW_NUMBER() OVER (PARTITION BY bpa.UserId ORDER BY bpa.EditOrRollbackCount DESC, bpa.PostLastActivityDate DESC) AS PostRankByEditCount,
    NULL AS QuestionEngagementIndex,
    COALESCE(CAST(bpa.PostScore AS NUMERIC) / NULLIF(bpa.EditOrRollbackCount, 0), 0.0) AS AnswerQualityMetric,
    CASE
        WHEN bpa.PostScore >= 20 AND bpa.EditOrRollbackCount >= 10 AND bpa.ParentQuestionStatus = 'Parent Accepted Answer' THEN 'Refined Accepted Answer'
        WHEN bpa.PostScore >= 10 AND bpa.EditOrRollbackCount >= 5 THEN 'Active Contribution'
        ELSE 'Minor Answer Edits'
    END AS AnswerCategory
FROM
    BasePostAnalysis AS bpa
WHERE
    bpa.PostTypeId = 2
    AND bpa.EditOrRollbackCount >= 5
    AND bpa.PostScore >= 10
    AND bpa.Reputation > 5000
    AND bpa.DaysSinceLastEdit <= 180
ORDER BY
    Reputation DESC,
    AnalysisType ASC,
    PostScore DESC
LIMIT 5000;