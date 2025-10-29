-- {"query": "1472.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2899}
WITH UserEngagementMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        CASE
            WHEN u.AboutMe LIKE '%developer%' OR u.AboutMe LIKE '%engineer%' OR u.AboutMe LIKE '%coding%' THEN TRUE
            ELSE FALSE
        END AS IsTechnicalUserInAboutMe,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        MAX(p.CreationDate) AS LastPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        (u.Reputation * 0.5) + (u.UpVotes * 0.2) - (u.DownVotes * 0.1) + (u.Views * 0.05) AS EngagementScore,
        RANK() OVER (ORDER BY (u.Reputation * 0.5 + u.UpVotes * 0.2 - u.DownVotes * 0.1) DESC) AS UserEngagementRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views,
        u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe
    HAVING COUNT(p.Id) > 5 AND SUM(COALESCE(p.Score, 0)) > 0
),
PostQualityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        p.LastEditDate,
        p.Title,
        p.AcceptedAnswerId,
        p.ParentId,
        (SELECT COALESCE(AVG(c.Score), 0) FROM Comments c WHERE c.PostId = p.Id AND c.Score IS NOT NULL) AS AverageCommentScore,
        -- parse tags string like '<tag1><tag2>' into array of lowercase trimmed tag names
        (SELECT ARRAY_AGG(TRIM(LOWER(tag))) FROM (SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), '><')) AS tag) AS tag_sub) AS TagArray,
        EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND (LOWER(c.Text) LIKE '%solution%' OR LOWER(c.Text) LIKE '%fix%')) AS HasSolutionComment,
        (p.ClosedDate IS NULL AND p.CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') AND p.ViewCount > 1000) AS IsOldAndOpenWithManyViews,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostTypeScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.OwnerUserId IS NOT NULL
      AND p.Score >= 0
),
RecentPostHistoryEvents AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryEventDate,
        ph.UserId AS HistoryUserId,
        ph.Comment AS HistoryComment,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryEventDate,
        CASE
            WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
            WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
            WHEN ph.PostHistoryTypeId = 5 THEN 'BodyEdited'
            WHEN ph.PostHistoryTypeId = 4 THEN 'TitleEdited'
            ELSE 'Other'
        END AS HistoryEventType
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 10, 11) AND ph.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '6 months')
),
LinkedPostAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS RegularLinksCount,
        MAX(CASE WHEN pl.LinkTypeId = 3 THEN rp.Score ELSE NULL END) AS MaxDuplicateLinkedScore,
        COALESCE(SUM(CASE WHEN pl.LinkTypeId = 1 THEN rp.ViewCount ELSE 0 END), 0) AS SumViewCountOfLinkedPosts
    FROM PostLinks pl
    LEFT JOIN Posts rp ON pl.RelatedPostId = rp.Id
    GROUP BY pl.PostId
),
QuestionAcceptedAnswerChain AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerId,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.CreationDate AS QuestionCreationDate,
        q.FavoriteCount AS QuestionFavoriteCount,
        aa.Id AS AcceptedAnswerId,
        aa.OwnerUserId AS AcceptedAnswerOwnerId,
        aa.Score AS AcceptedAnswerScore,
        aa.CreationDate AS AcceptedAnswerCreationDate,
        (aa.CreationDate - q.CreationDate) AS TimeToAcceptAnswer,
        (q.OwnerUserId = aa.OwnerUserId) AS SelfAcceptedAnswer,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = aa.Id AND c.UserId = q.OwnerUserId AND c.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '1 year')) AS QuestionOwnerRecentCommentsOnAcceptedAnswer
    FROM Posts q
    JOIN Posts aa ON q.AcceptedAnswerId = aa.Id
    WHERE q.PostTypeId = 1 AND aa.PostTypeId = 2 AND q.AcceptedAnswerId IS NOT NULL
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.EngagementScore,
    ue.UserEngagementRank,
    ue.TotalBadges,
    ue.GoldBadges,
    ue.IsTechnicalUserInAboutMe,
    ue.UserLocation,
    pq.PostId,
    pq.PostTypeId,
    pq.PostScore,
    pq.ViewCount AS PostViewCount,
    pq.AverageCommentScore,
    pq.HasSolutionComment,
    pq.IsOldAndOpenWithManyViews,
    pq.PostTypeScoreRank,
    pq.Title AS PostTitle,
    pq.PostCreationDate AS PostCreationDate,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - pq.LastActivityDate)) / 3600 AS HoursSinceLastActivity,
    STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS RelatedTags,
    lp.TotalLinkedPosts,
    lp.DuplicateLinksCount,
    lp.MaxDuplicateLinkedScore,
    lp.SumViewCountOfLinkedPosts,
    qac.QuestionId,
    qac.QuestionTitle,
    qac.QuestionScore,
    qac.QuestionViewCount,
    qac.AcceptedAnswerId,
    qac.AcceptedAnswerScore,
    qac.TimeToAcceptAnswer,
    qac.SelfAcceptedAnswer,
    qac.QuestionOwnerRecentCommentsOnAcceptedAnswer,
    ROW_NUMBER() OVER (PARTITION BY ue.UserId ORDER BY pq.PostScore DESC, pq.PostCreationDate DESC) AS UserPostScoreRank,
    (
        SELECT c.Text
        FROM Comments c
        WHERE c.PostId = pq.PostId
          AND c.UserId = ue.UserId
          AND c.CreationDate = (SELECT MAX(c2.CreationDate) FROM Comments c2 WHERE c2.PostId = pq.PostId AND c2.UserId = ue.UserId)
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS LatestOwnerComment,
    (
        SELECT COUNT(DISTINCT rph.HistoryEventDate)
        FROM RecentPostHistoryEvents rph
        WHERE rph.PostId = pq.PostId
          AND rph.HistoryEventType IN ('Closed', 'Reopened')
    ) AS ClosedReopenedEventCount,
    (
        SELECT u_editor.DisplayName
        FROM Posts p_editor
        JOIN Users u_editor ON p_editor.LastEditorUserId = u_editor.Id
        WHERE p_editor.Id = pq.PostId
          AND p_editor.LastEditorUserId IS NOT NULL
          AND p_editor.LastEditorUserId != ue.UserId
        LIMIT 1
    ) AS LastEditorDisplayNameIfDifferent,
    COALESCE(
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = pq.PostId AND v.VoteTypeId = 8),
        0
    ) AS TotalBountyAmountOnPost,
    (
        SELECT AVG(EXTRACT(EPOCH FROM (rph_curr.HistoryEventDate - rph_prev.HistoryEventDate)) / 3600)
        FROM RecentPostHistoryEvents rph_curr
        JOIN RecentPostHistoryEvents rph_prev ON rph_curr.PostId = rph_prev.PostId AND rph_curr.PreviousHistoryEventDate = rph_prev.HistoryEventDate
        WHERE rph_curr.PostId = pq.PostId
          AND rph_curr.HistoryEventType IN ('BodyEdited', 'TitleEdited')
          AND rph_prev.HistoryEventType IN ('BodyEdited', 'TitleEdited')
    ) AS AvgHoursBetweenEdits
FROM UserEngagementMetrics ue
JOIN PostQualityMetrics pq ON ue.UserId = pq.OwnerUserId
LEFT JOIN LATERAL (SELECT UNNEST(pq.TagArray) AS TagName) AS t ON TRUE
LEFT JOIN LinkedPostAnalysis lp ON pq.PostId = lp.PostId
LEFT JOIN QuestionAcceptedAnswerChain qac ON pq.PostId = qac.QuestionId OR pq.PostId = qac.AcceptedAnswerId
WHERE
    ue.EngagementScore > 2000
    AND pq.PostScore > 25
    AND ((pq.PostTypeId = 1 AND pq.ViewCount > 1000) OR (pq.PostTypeId = 2 AND pq.HasSolutionComment))
    AND (
        (pq.TagArray IS NOT NULL AND EXISTS (SELECT 1 FROM UNNEST(pq.TagArray) AS t_check(tag) WHERE tag IN ('sql', 'postgresql', 'performance', 'indexing')))
        OR (pq.TagArray IS NOT NULL AND 'query-optimization' = ANY(pq.TagArray))
    )
    AND pq.PostCreationDate > (CAST('2024-10-01' AS date) - INTERVAL '3 years')
    AND ue.LastAccessDate > (CAST('2024-10-01' AS date) - INTERVAL '6 months')
    AND ue.UserLocation IS NOT NULL
    AND COALESCE(lp.DuplicateLinksCount, 0) <= 2
    AND (pq.PostTypeId = 1 OR pq.AcceptedAnswerId IS NULL)
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.EngagementScore, ue.UserEngagementRank, ue.TotalBadges,
    ue.GoldBadges, ue.IsTechnicalUserInAboutMe, ue.UserLocation, pq.PostId, pq.PostTypeId, pq.PostScore,
    pq.ViewCount, pq.AverageCommentScore, pq.HasSolutionComment, pq.IsOldAndOpenWithManyViews, pq.PostTypeScoreRank,
    pq.Title, pq.PostCreationDate, pq.LastActivityDate, lp.TotalLinkedPosts, lp.DuplicateLinksCount,
    lp.MaxDuplicateLinkedScore, lp.SumViewCountOfLinkedPosts, qac.QuestionId, qac.QuestionTitle, qac.QuestionScore, qac.QuestionViewCount,
    qac.AcceptedAnswerId, qac.AcceptedAnswerScore, qac.TimeToAcceptAnswer, qac.SelfAcceptedAnswer,
    qac.QuestionOwnerRecentCommentsOnAcceptedAnswer
HAVING COUNT(DISTINCT t.TagName) > 1
ORDER BY
    ue.EngagementScore DESC,
    pq.PostScore DESC,
    HoursSinceLastActivity ASC
LIMIT 1000;