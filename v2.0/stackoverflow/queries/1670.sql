-- {"query": "1670.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3547}
WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Views, 0) AS UserViews,
        COALESCE(u.UpVotes, 0) AS UserUpVotes,
        COALESCE(u.DownVotes, 0) AS UserDownVotes,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AnswersAccepted,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END), 0.0) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        MAX(GREATEST(p.LastActivityDate, c.CreationDate)) AS LastContentActivity,
        (u.Reputation * 0.5) + (COUNT(DISTINCT p.Id) * 0.2) + (COUNT(DISTINCT c.Id) * 0.1) + (COALESCE(SUM(p.Score), 0) * 0.15) + (COALESCE(SUM(c.Score), 0) * 0.05) AS ActivityScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts q ON p.PostTypeId = 2 AND p.ParentId = q.Id
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS BuiltinCommentCount,
        p.FavoriteCount AS BuiltinFavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COALESCE(COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)), 0) AS DistinctEditorCount,
        COALESCE(edits.AvgSecondsBetweenEdits, 0.0) AS AvgSecondsBetweenEdits,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END), 0) AS PositiveVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId IN (3, 4, 10, 12) THEN 1 ELSE 0 END), 0) AS NegativeVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteBookmarks,
        (SELECT ph_inner.Comment FROM PostHistory ph_inner WHERE ph_inner.PostId = p.Id AND ph_inner.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) ORDER BY ph_inner.CreationDate DESC LIMIT 1) AS LatestCloseReasonComment,
        COALESCE(pl_linked.LinkedPostsCount, 0) AS TotalLinkedPosts,
        COALESCE(pl_duplicate.DuplicateOfPostsCount, 0) AS TotalDuplicateOfPosts,
        CASE
            WHEN p.Body LIKE '%<a href="http%' OR p.Body LIKE '%<a href="https%' THEN 'HasExternalLink'
            WHEN p.Body LIKE '%<img src%' THEN 'HasImage'
            ELSE 'NoSpecialContent'
        END AS BodyContentIndicator
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN (SELECT RelatedPostId, COUNT(Id) AS LinkedPostsCount FROM PostLinks WHERE LinkTypeId = 1 GROUP BY RelatedPostId) pl_linked ON p.Id = pl_linked.RelatedPostId
    LEFT JOIN (SELECT RelatedPostId, COUNT(Id) AS DuplicateOfPostsCount FROM PostLinks WHERE LinkTypeId = 3 GROUP BY RelatedPostId) pl_duplicate ON p.Id = pl_duplicate.RelatedPostId
    LEFT JOIN (
        SELECT
            ph2.PostId,
            AVG(EXTRACT(EPOCH FROM (ph2.CreationDate - ph2.PrevCreationDate))) AS AvgSecondsBetweenEdits
        FROM (
            SELECT
                ph_inner.PostId,
                ph_inner.CreationDate,
                LAG(ph_inner.CreationDate) OVER (PARTITION BY ph_inner.PostId ORDER BY ph_inner.CreationDate) AS PrevCreationDate,
                ph_inner.PostHistoryTypeId
            FROM PostHistory ph_inner
            WHERE ph_inner.PostHistoryTypeId IN (4,5,6)
        ) ph2
        WHERE ph2.PrevCreationDate IS NOT NULL
        GROUP BY ph2.PostId
    ) edits ON p.Id = edits.PostId
    GROUP BY p.Id, p.PostTypeId, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.Body, edits.AvgSecondsBetweenEdits, pl_linked.LinkedPostsCount, pl_duplicate.DuplicateOfPostsCount
),
TagUsageStats AS (
    SELECT
        qt.TagName,
        COUNT(DISTINCT qt.PostId) AS QuestionsTagged,
        COALESCE(AVG(qt.Score), 0.0) AS AvgScoreForTag,
        COUNT(DISTINCT qt.OwnerUserId) AS UniqueAuthorsUsingTag,
        MIN(qt.CreationDate) AS FirstTagUseDate,
        MAX(qt.CreationDate) AS LastTagUseDate
    FROM (
        SELECT
            p.Id AS PostId,
            p.CreationDate,
            p.Score,
            p.OwnerUserId,
            TRIM(unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    ) AS qt
    GROUP BY qt.TagName
    HAVING COUNT(DISTINCT qt.PostId) > 10
),
RecentCommentSummary AS (
    SELECT
        c.PostId,
        c.Text AS LastCommentText,
        c.CreationDate AS LastCommentDate,
        c.UserId AS LastCommenterId,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
    FROM Comments c
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalQuestionsPosted,
    ues.TotalAnswersPosted,
    ues.TotalPostScore,
    ues.AvgPostScore,
    ues.QuestionsWithAcceptedAnswer,
    ues.AnswersAccepted,
    ues.TotalCommentsMade,
    ues.TotalCommentScore,
    ues.LastContentActivity,
    ues.ActivityScore,
    pm.PostId,
    pm.PostTypeId,
    pm.PostCreationDate,
    pm.PostScore,
    pm.ViewCount,
    pm.BuiltinCommentCount,
    pm.DistinctEditorCount,
    pm.AvgSecondsBetweenEdits,
    pm.PositiveVotes,
    pm.NegativeVotes,
    pm.FavoriteBookmarks,
    pm.LatestCloseReasonComment,
    pm.TotalLinkedPosts,
    pm.TotalDuplicateOfPosts,
    pm.BodyContentIndicator,
    COALESCE(rcs.LastCommentText, 'No recent comment') AS LatestPostComment,
    COALESCE(rcs.LastCommentDate, pm.PostCreationDate) AS LatestPostCommentDate,
    COALESCE(t.TagName, 'Untagged/Generic') AS TopUsedTag,
    t.Count AS TopUsedTagGlobalCount,
    tus.AvgScoreForTag AS TopUsedTagAvgQuestionScore,
    (TIMESTAMP '2024-10-01 12:34:56' - ues.UserCreationDate) AS UserAge,
    (pm.PositiveVotes * 1.0 / NULLIF(pm.PositiveVotes + pm.NegativeVotes, 0)) AS NetVoteRatio,
    CASE
        WHEN u.Location LIKE '%United States%' THEN 'USA'
        WHEN u.Location LIKE '%Canada%' THEN 'Canada'
        WHEN u.Location LIKE '%India%' THEN 'India'
        WHEN u.Location IS NULL OR u.Location = '' THEN 'Unknown'
        ELSE 'Other'
    END AS UserLocationCategory,
    ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY pm.PostScore DESC, pm.ViewCount DESC, pm.BuiltinCommentCount DESC) AS PostEngagementRankByUser,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     WHERE pl.LinkTypeId = 3 AND pl.RelatedPostId = pm.PostId AND pm.PostTypeId = 1
    ) AS IsDuplicateSourceCount
FROM UserEngagementSummary ues
JOIN Users u ON ues.UserId = u.Id
LEFT JOIN PostMetrics pm ON ues.UserId = pm.OwnerUserId
LEFT JOIN RecentCommentSummary rcs ON pm.PostId = rcs.PostId AND rcs.rn = 1
LEFT JOIN (
    SELECT
        qt.OwnerUserId,
        qt.TagName,
        t.Count,
        ROW_NUMBER() OVER (PARTITION BY qt.OwnerUserId ORDER BY COUNT(qt.PostId) DESC, qt.TagName) AS rn
    FROM (
        SELECT
            p.Id AS PostId,
            p.OwnerUserId,
            TRIM(unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.OwnerUserId IS NOT NULL
    ) AS qt
    JOIN Tags t ON qt.TagName = t.TagName
    GROUP BY qt.OwnerUserId, qt.TagName, t.Count
) AS t ON ues.UserId = t.OwnerUserId AND t.rn = 1
LEFT JOIN TagUsageStats tus ON t.TagName = tus.TagName
WHERE ues.Reputation > 1000
  AND ues.TotalQuestionsPosted + ues.TotalAnswersPosted > 0
  AND pm.PostId IS NOT NULL
  AND pm.PostCreationDate >= DATE '2020-01-01'
  AND (pm.ViewCount > 500 OR pm.PostScore > 10)
  AND NOT EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = ues.UserId AND b.Name = 'Disciplined'
  )
  AND (pm.LatestCloseReasonComment IS NULL OR pm.LatestCloseReasonComment NOT LIKE '%off-topic%')

UNION ALL

SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalQuestionsPosted,
    ues.TotalAnswersPosted,
    ues.TotalPostScore,
    ues.AvgPostScore,
    ues.QuestionsWithAcceptedAnswer,
    ues.AnswersAccepted,
    ues.TotalCommentsMade,
    ues.TotalCommentScore,
    ues.LastContentActivity,
    ues.ActivityScore,
    pm.PostId,
    pm.PostTypeId,
    pm.PostCreationDate,
    pm.PostScore,
    pm.ViewCount,
    pm.BuiltinCommentCount,
    pm.DistinctEditorCount,
    pm.AvgSecondsBetweenEdits,
    pm.PositiveVotes,
    pm.NegativeVotes,
    pm.FavoriteBookmarks,
    pm.LatestCloseReasonComment,
    pm.TotalLinkedPosts,
    pm.TotalDuplicateOfPosts,
    pm.BodyContentIndicator,
    COALESCE(rcs.LastCommentText, 'No recent comment') AS LatestPostComment,
    COALESCE(rcs.LastCommentDate, pm.PostCreationDate) AS LatestPostCommentDate,
    COALESCE(t.TagName, 'Untagged/Generic') AS TopUsedTag,
    t.Count AS TopUsedTagGlobalCount,
    tus.AvgScoreForTag AS TopUsedTagAvgQuestionScore,
    (TIMESTAMP '2024-10-01 12:34:56' - ues.UserCreationDate) AS UserAge,
    (pm.PositiveVotes * 1.0 / NULLIF(pm.PositiveVotes + pm.NegativeVotes, 0)) AS NetVoteRatio,
    CASE
        WHEN u.Location LIKE '%United States%' THEN 'USA'
        WHEN u.Location LIKE '%Canada%' THEN 'Canada'
        WHEN u.Location LIKE '%India%' THEN 'India'
        WHEN u.Location IS NULL OR u.Location = '' THEN 'Unknown'
        ELSE 'Other'
    END AS UserLocationCategory,
    ROW_NUMBER() OVER (PARTITION BY ues.UserId ORDER BY pm.PostScore DESC, pm.ViewCount DESC, pm.BuiltinCommentCount DESC) AS PostEngagementRankByUser,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     WHERE pl.LinkTypeId = 3 AND pl.RelatedPostId = pm.PostId AND pm.PostTypeId = 1
    ) AS IsDuplicateSourceCount
FROM UserEngagementSummary ues
JOIN Users u ON ues.UserId = u.Id
JOIN PostMetrics pm ON ues.UserId = pm.OwnerUserId
LEFT JOIN RecentCommentSummary rcs ON pm.PostId = rcs.PostId AND rcs.rn = 1
LEFT JOIN (
    SELECT
        qt.OwnerUserId,
        qt.TagName,
        t.Count,
        ROW_NUMBER() OVER (PARTITION BY qt.OwnerUserId ORDER BY COUNT(qt.PostId) DESC, qt.TagName) AS rn
    FROM (
        SELECT
            p.Id AS PostId,
            p.OwnerUserId,
            TRIM(unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.OwnerUserId IS NOT NULL
    ) AS qt
    JOIN Tags t ON qt.TagName = t.TagName
    GROUP BY qt.OwnerUserId, qt.TagName, t.Count
) AS t ON ues.UserId = t.OwnerUserId AND t.rn = 1
LEFT JOIN TagUsageStats tus ON t.TagName = tus.TagName
WHERE pm.PostTypeId = 2
  AND pm.PositiveVotes > 50
  AND ues.TotalQuestionsPosted < 5
  AND u.Reputation > 500
  AND pm.PostCreationDate >= DATE '2021-01-01'
  AND pm.ClosedDate IS NULL
  AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_mig
        WHERE ph_mig.PostId = pm.PostId AND ph_mig.PostHistoryTypeId IN (35, 36)
  )
ORDER BY Reputation DESC, ActivityScore DESC, LatestPostCommentDate DESC;