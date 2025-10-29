-- {"query": "1970.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2514} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p_q.Id) AS QuestionCount,
        COUNT(DISTINCT p_a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(COALESCE(p_q.Score, 0)) AS TotalQuestionScore,
        SUM(COALESCE(p_a.Score, 0)) AS TotalAnswerScore,
        MAX(GREATEST(
            COALESCE(p_q.LastActivityDate, '1900-01-01'::timestamp),
            COALESCE(p_a.LastActivityDate, '1900-01-01'::timestamp),
            COALESCE(c.CreationDate, '1900-01-01'::timestamp),
            u.LastAccessDate
        )) AS LastContentActivityDate
    FROM Users u
    LEFT JOIN Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = 1
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
        u.CreationDate, u.LastAccessDate
    HAVING
        u.Reputation > 5000 OR COUNT(DISTINCT p_q.Id) + COUNT(DISTINCT p_a.Id) > 100
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount AS PostAnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes, -- UpMod
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes, -- DownMod
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoriteVotes, -- Old Favorite
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 'Closed'
                 WHEN ph_reopen.PostHistoryTypeId = 11 THEN 'Reopened'
                 ELSE NULL END) AS CurrentPostStatus,
        COUNT(DISTINCT ph_close.Id) AS CloseHistoryCount,
        COUNT(DISTINCT ph_reopen.Id) AS ReopenHistoryCount,
        MAX(ph_close.CreationDate) AS LastClosedDate,
        MAX(ph_reopen.CreationDate) AS LastReopenedDate
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 5) -- UpMod, DownMod, Favorite (old)
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10 -- Post Closed
    LEFT JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11 -- Post Reopened
    WHERE p.PostTypeId = 1 -- Focus on Questions
    GROUP BY
        p.Id, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
),
RecentPostHistoryEvents AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EventDate,
        ph.Comment AS EventComment,
        ph.Text AS EventDetails,
        ph_type.Name AS EventTypeName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes ph_type ON ph.PostHistoryTypeId = ph_type.Id
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 33, 34, 35, 36) -- Significant events
),
AllQuestionTags AS (
    SELECT
        p.Id AS PostId,
        TRIM(unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagPerformanceStats AS (
    SELECT
        aqt.TagName,
        COUNT(DISTINCT aqt.PostId) AS TaggedQuestionCount,
        AVG(p.Score) AS AvgTagQuestionScore,
        AVG(p.ViewCount) AS AvgTagQuestionViews,
        MAX(p.CreationDate) AS LastTaggedQuestionDate
    FROM AllQuestionTags aqt
    JOIN Posts p ON aqt.PostId = p.Id
    GROUP BY aqt.TagName
    HAVING COUNT(DISTINCT aqt.PostId) > 100 -- Only consider tags with substantial usage
)
SELECT
    uas.UserId,
    uas.DisplayName AS UserDisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    q.Id AS QuestionId,
    SUBSTRING(q.Title, 1, 100) AS QuestionTitlePreview,
    q.CreationDate AS QuestionCreationDate,
    q.Score AS QuestionCurrentScore,
    pem.ViewCount AS QuestionViewCount,
    pem.TotalUpVotes AS QuestionTotalUpVotes,
    pem.TotalDownVotes AS QuestionTotalDownVotes,
    COALESCE(pem.PostFavoriteCount, pem.TotalFavoriteVotes, 0) AS QuestionFavoriteCountTotal,
    rphe.EventTypeName AS LastHistoryEventType,
    rphe.EventDate AS LastHistoryEventDate,
    COALESCE(rphe.EventComment, LEFT(COALESCE(rphe.EventDetails, ''), 100)) AS LastHistoryEventInfo,
    (SELECT AVG(ans.Score)
     FROM Posts ans
     WHERE ans.ParentId = q.Id
       AND ans.PostTypeId = 2
       AND ans.Score > 0
       AND q.AnswerCount > 2) AS AvgPositiveAnswerScoreForQuestion,
    NTILE(5) OVER (ORDER BY (COALESCE(pem.TotalUpVotes,0) + COALESCE(pem.PostFavoriteCount,0)) DESC, q.ViewCount DESC) AS EngagementQuintile,
    LAG(q.CreationDate, 1, NULL) OVER (PARTITION BY uas.UserId ORDER BY q.CreationDate) AS PreviousQuestionDate,
    EXTRACT(DAY FROM (q.CreationDate - LAG(q.CreationDate, 1, q.CreationDate) OVER (PARTITION BY uas.UserId ORDER BY q.CreationDate))) AS DaysSincePreviousQuestion,
    (
        SELECT tp.TagName
        FROM AllQuestionTags aqt_inner
        JOIN TagPerformanceStats tp ON aqt_inner.TagName = tp.TagName
        WHERE aqt_inner.PostId = q.Id
        ORDER BY tp.AvgTagQuestionScore DESC, tp.TaggedQuestionCount DESC
        LIMIT 1
    ) AS TopPerformingTagInQuestion,
    CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rphe.PostHistoryTypeId = 11 AND rphe.EventDate > q.CreationDate THEN 'Reopened'
        WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN uas.Reputation > 10000 AND COALESCE(q.FavoriteCount,0) > 50 THEN 'High Value & Popular'
        ELSE 'Active'
    END AS PostLifecycleStatus,
    CASE
        WHEN q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<database>%' OR q.Tags LIKE '%<postgresql>%' THEN 'Database Related'
        WHEN q.Tags LIKE '%<python>%' OR q.Tags LIKE '%<java>%' OR q.Tags LIKE '%<javascript>%' THEN 'Programming Language'
        WHEN q.Tags LIKE '%<azure>%' OR q.Tags LIKE '%<aws>%' THEN 'Cloud Platform'
        ELSE 'Other Technical'
    END AS TagCategory
FROM UserActivitySummary uas
JOIN Posts q ON uas.UserId = q.OwnerUserId AND q.PostTypeId = 1
LEFT JOIN PostEngagementMetrics pem ON q.Id = pem.PostId
LEFT JOIN RecentPostHistoryEvents rphe ON q.Id = rphe.PostId AND rphe.rn = 1
WHERE
    q.CreationDate BETWEEN (CURRENT_DATE - INTERVAL '2 year') AND CURRENT_DATE
    AND q.ViewCount > 500
    AND (q.AnswerCount IS NULL OR q.AnswerCount <= 50) -- Exclude posts with extremely high answer counts
    AND (q.LastActivityDate IS NOT NULL AND q.LastActivityDate > (CURRENT_DATE - INTERVAL '6 months')) -- Recently active
    AND (
        (uas.Reputation > 15000 AND uas.QuestionCount > 50) OR
        (q.Score > 75 AND pem.TotalUpVotes > 150) OR
        (COALESCE(q.FavoriteCount,0) > 30 AND q.ViewCount > 10000)
    )
    -- Ensure question uses at least one high-performing popular tag
    AND EXISTS (
        SELECT 1
        FROM AllQuestionTags aqt_outer
        JOIN TagPerformanceStats tps ON aqt_outer.TagName = tps.TagName
        WHERE aqt_outer.PostId = q.Id AND tps.AvgTagQuestionScore > 10 AND tps.TaggedQuestionCount > 500
    )
    -- Exclude posts that were deleted much later, indicating potential long-term content issues
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_del
        WHERE ph_del.PostId = q.Id
          AND ph_del.PostHistoryTypeId = 12 -- Post Deleted
          AND ph_del.CreationDate > (q.CreationDate + INTERVAL '180 days')
    )
ORDER BY
    EngagementQuintile ASC,
    uas.Reputation DESC,
    QuestionCreationDate DESC
LIMIT 7500;
