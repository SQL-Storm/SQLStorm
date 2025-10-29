WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(COALESCE(p.LastActivityDate, c.CreationDate, u.LastAccessDate)) AS LastInteractionDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation >= 1500
      AND u.LastAccessDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
    HAVING COUNT(DISTINCT p.Id) > 7 OR COUNT(DISTINCT c.Id) > 15
),
HotPostHistory AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        ARRAY_AGG(DISTINCT ph.UserId) FILTER (WHERE ph.UserId IS NOT NULL) AS DistinctEditors,
        STRING_AGG(DISTINCT ph.Comment, '; ') FILTER (WHERE ph.Comment IS NOT NULL AND ph.PostHistoryTypeId = 10) AS CloseReasonsConcat
    FROM PostHistory ph
    WHERE ph.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '3 years'
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 5
),
TagPerformance AS (
    SELECT
        tag AS TagName,
        AVG(p.Score) AS AvgTagScore,
        AVG(p.ViewCount) AS AvgTagViewCount,
        COUNT(p.Id) AS TagPostCount
    FROM Posts p,
         UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    WHERE p.Tags IS NOT NULL
      AND p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '4 years'
    GROUP BY tag
    HAVING COUNT(p.Id) > 200
),
HighlyEngagedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.Body,
        p.AcceptedAnswerId,
        p.ClosedDate,
        CAST(NULL AS BIGINT) AS ParentId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '6 years'
      AND p.ViewCount > 20000
      AND p.AnswerCount >= 7
    UNION ALL
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.Body,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.ParentId
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '6 years'
      AND p.Score > 75
),
BadgeCounts AS (
    SELECT
        UserId,
        COUNT(Id) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Badges
    GROUP BY UserId
),
PostLinkCounts AS (
    SELECT
        PostId,
        COUNT(CASE WHEN LinkTypeId = 1 THEN 1 END) AS LinkedPostsCount,
        COUNT(CASE WHEN LinkTypeId = 3 THEN 1 END) AS DuplicatePostsCount
    FROM PostLinks
    GROUP BY PostId
)
SELECT
    uas.DisplayName AS AuthorDisplayName,
    uas.Reputation,
    uas.UpVotes AS AuthorUpVotes,
    uas.DownVotes AS AuthorDownVotes,
    hep.PostId,
    hep.Title AS PostTitle,
    hep.CreationDate AS PostCreationDate,
    hep.Score AS PostScore,
    hep.ViewCount AS PostViewCount,
    hep.AnswerCount,
    hep.CommentCount AS PostCommentCount,
    hep.FavoriteCount,
    pt.Name AS PostTypeName,
    COALESCE(hep.Tags, '[No Tags Specified]') AS PostTags,
    hph.EditCount,
    hph.CloseCount,
    hph.ReopenCount,
    hph.LastHistoryEventDate,
    hph.CloseReasonsConcat,
    tp.AvgTagScore,
    tp.AvgTagViewCount,
    tp.TagPostCount,
    b.BadgeCount AS UserBadgeCount,
    b.GoldBadgeCount,
    b.SilverBadgeCount,
    b.BronzeBadgeCount,
    pl.LinkedPostsCount,
    pl.DuplicatePostsCount,
    (SELECT COUNT(DISTINCT ph_sub.UserId)
     FROM PostHistory ph_sub
     WHERE ph_sub.PostId = hep.PostId
       AND ph_sub.PostHistoryTypeId IN (4,5,6)
       AND ph_sub.CreationDate >= hep.CreationDate) AS UniqueEditorsAfterCreation,
    AVG(hep.Score) OVER (PARTITION BY uas.UserId ORDER BY hep.CreationDate) AS UserAvgPostScoreRolling,
    RANK() OVER (PARTITION BY pt.Name ORDER BY hep.Score DESC, COALESCE(hep.ViewCount, 0) DESC) AS RankInPostType,
    LAG(hep.CreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY uas.UserId ORDER BY hep.CreationDate) AS PreviousPostDate,
    EXTRACT(EPOCH FROM (hep.CreationDate - LAG(hep.CreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY uas.UserId ORDER BY hep.CreationDate))) / 86400.0 AS DaysSincePreviousPost,
    CASE
        WHEN hep.PostTypeId = 1 AND hep.ClosedDate IS NOT NULL AND hep.AcceptedAnswerId IS NULL THEN 'Question_Closed_NoAcceptedAnswer'
        WHEN hep.PostTypeId = 1 AND hep.ClosedDate IS NULL AND hep.AcceptedAnswerId IS NOT NULL THEN 'Question_Open_AcceptedAnswer'
        WHEN hep.PostTypeId = 1 AND hep.ClosedDate IS NOT NULL AND hep.AcceptedAnswerId IS NOT NULL THEN 'Question_Closed_AcceptedAnswer'
        WHEN hep.PostTypeId = 1 THEN 'Question_Open_NoAcceptedAnswer'
        WHEN hep.PostTypeId = 2 AND hep.ParentId IS NOT NULL AND EXISTS (SELECT 1 FROM Posts acc_p WHERE acc_p.Id = hep.ParentId AND acc_p.AcceptedAnswerId = hep.PostId) THEN 'Answer_AcceptedByOriginator'
        WHEN hep.PostTypeId = 2 AND hep.ParentId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Posts acc_p WHERE acc_p.Id = hep.ParentId AND acc_p.AcceptedAnswerId = hep.PostId) THEN 'Answer_NotAcceptedByOriginator'
        ELSE 'Post_Status_Unknown'
    END AS PostStatusFlag,
    (SELECT MAX(c_sub.CreationDate) FROM Comments c_sub WHERE c_sub.PostId = hep.PostId AND c_sub.UserId IS NOT NULL) AS LatestCommentDateByKnownUser,
    NULLIF(hep.AnswerCount, 0) * hep.Score AS WeightedPostImpactScore,
    COALESCE(uas.DisplayName, 'Unknown User ' || uas.UserId) AS GuaranteedAuthorDisplay
FROM UserActivitySummary uas
INNER JOIN HighlyEngagedPosts hep ON uas.UserId = hep.OwnerUserId
INNER JOIN PostTypes pt ON hep.PostTypeId = pt.Id
LEFT JOIN HotPostHistory hph ON hep.PostId = hph.PostId
LEFT JOIN LATERAL (
    SELECT
        tp.AvgTagScore,
        tp.AvgTagViewCount,
        tp.TagPostCount
    FROM TagPerformance tp
    WHERE hep.Tags IS NOT NULL
      AND tp.TagName IS NOT NULL
      AND hep.Tags LIKE '%' || '<' || tp.TagName || '>' || '%'
    ORDER BY tp.TagPostCount DESC
    LIMIT 1
) tp ON TRUE
LEFT JOIN BadgeCounts b ON uas.UserId = b.UserId
LEFT JOIN PostLinkCounts pl ON hep.PostId = pl.PostId
WHERE hep.PostTypeId IN (1, 2)
  AND (hep.Body LIKE '%complex query%' OR hep.Tags LIKE '%<performance>%' OR hep.Title LIKE '%optimization%' OR hep.Body LIKE '%benchmarking%')
  AND (hep.OwnerUserId IS NOT NULL OR uas.DisplayName IS NOT NULL)
ORDER BY uas.Reputation DESC, hep.Score DESC, COALESCE(hep.ViewCount, 0) DESC, hep.CreationDate DESC
LIMIT 500;