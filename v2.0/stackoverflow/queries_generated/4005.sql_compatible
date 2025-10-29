WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
RecentActivity AS (
    SELECT
        PostId,
        MAX(CreationDate) AS LastActivityOnPost
    FROM PostHistory
    GROUP BY PostId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upc.TotalPosts, 0) AS TotalUserPosts,
        COALESCE(upc.QuestionCount, 0) AS UserQuestionCount,
        COALESCE(upc.AnswerCount, 0) AS UserAnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpvotesGiven,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS TotalDownvotesGiven,
        ra.LastActivityOnPost
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    LEFT JOIN (
        SELECT
            ph.UserId,
            MAX(ph.CreationDate) AS LastActivityOnPost
        FROM PostHistory ph
        GROUP BY ph.UserId
    ) ra ON u.Id = ra.UserId
    WHERE u.Id > 0
),
-- materialize the scalar subqueries for close reason to avoid non-inner join on subquery issues
PostLatestClose AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastCloseDate,
        MAX(CASE WHEN ph.CreationDate = MAX_PH.MaxCreation THEN ph.Comment END) AS LastCloseComment
    FROM PostHistory ph
    JOIN (
        SELECT PostId, MAX(CreationDate) AS MaxCreation
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
        GROUP BY PostId
    ) MAX_PH ON ph.PostId = MAX_PH.PostId
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
PostLastVote AS (
    SELECT v.PostId, v.VoteTypeId, v.UserId
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
),
-- unify posts of two different pt.Name sets via single query selecting all relevant names
FilteredPosts AS (
    SELECT *
    FROM Posts
    WHERE PostTypeId IS NOT NULL
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COALESCE(p.Score, 0) AS PostScore,
    COALESCE(p.ViewCount, 0) AS PostViewCount,
    COALESCE(p.AnswerCount, 0) AS PostAnswerCount,
    COALESCE(p.CommentCount, 0) AS PostCommentCount,
    COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate AS PostLastActivityDate,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    COALESCE(pte.Name, 'N/A') AS PrimaryCloseReason,
    COALESCE(plv.VoteTypeId, 0) AS LastVoteType,
    COALESCE(up.DisplayName, 'Community') AS LastEditorDisplayName,
    COALESCE(uas.UserQuestionCount, 0) AS OwnerUserTotalQuestions,
    COALESCE(uas.UserAnswerCount, 0) AS OwnerUserTotalAnswers,
    COALESCE(uas.TotalUpvotesGiven, 0) AS OwnerTotalUpvotesGiven,
    COALESCE(uas.TotalDownvotesGiven, 0) AS OwnerTotalDownvotesGiven,
    COALESCE(ph_title_edit.CreationDate, TIMESTAMP '1970-01-01 00:00:00') AS LastTitleEditDate,
    COALESCE(ph_body_edit.CreationDate, TIMESTAMP '1970-01-01 00:00:00') AS LastBodyEditDate,
    CAST(
        CASE
            WHEN p.Tags IS NULL THEN 'No Tags'
            WHEN LENGTH(p.Tags) > 100 THEN SUBSTRING(p.Tags FROM 1 FOR 100) || '...'
            ELSE p.Tags
        END AS VARCHAR(200)
    ) AS TruncatedTags,
    UPPER(SUBSTRING(COALESCE(p.ContentLicense, 'UNKNOWN') FROM 1 FOR 3)) AS ContentLicenseAbbreviation,
    CASE
        WHEN LENGTH(COALESCE(p.Body, '')) > 1000 THEN MD5(SUBSTRING(p.Body FROM 1 FOR 1000))
        ELSE MD5(COALESCE(p.Body, ''))
    END AS BodyHashSample
FROM FilteredPosts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLatestClose plc ON p.Id = plc.PostId
LEFT JOIN CloseReasonTypes pte ON pte.Id = CAST(plc.LastCloseComment AS INTEGER)
LEFT JOIN (
    SELECT v.PostId, v.VoteTypeId, v.UserId
    FROM Votes v
    WHERE v.VoteTypeId IN (2,3)
) plv ON p.Id = plv.PostId AND plv.UserId = u.Id
LEFT JOIN Users up ON p.LastEditorUserId = up.Id
LEFT JOIN UserActivitySummary uas ON p.OwnerUserId = uas.UserId
LEFT JOIN RankedPostEdits ph_title_edit ON p.Id = ph_title_edit.PostId AND ph_title_edit.PostHistoryTypeId = 4 AND ph_title_edit.rn = 1
LEFT JOIN RankedPostEdits ph_body_edit ON p.Id = ph_body_edit.PostId AND ph_body_edit.PostHistoryTypeId = 5 AND ph_body_edit.rn = 1
WHERE pt.Name IN ('Question', 'Answer', 'TagWikiExcerpt', 'TagWiki')
ORDER BY PostCreationDate DESC
LIMIT 1000;