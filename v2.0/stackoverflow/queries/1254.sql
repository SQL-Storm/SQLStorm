-- {"query": "1254.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2444}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(p.LastEditDate) AS LastPostEditDate,
        COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueHistoryTypes,
        NULLIF(u.UpVotes, 0) AS UserUpVotes,
        NULLIF(u.DownVotes, 0) AS UserDownVotes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6,10,11,12,13)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.UpVotes, u.DownVotes
    HAVING COUNT(p.Id) > 5 AND u.Reputation > 1000
), PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount,
        COUNT(DISTINCT pl_linked.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT pl_duplicate.RelatedPostId) AS DuplicatePostCount,
        MIN(c.CreationDate) AS FirstCommentDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3,5)
    LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
    LEFT JOIN PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
    GROUP BY p.Id
    HAVING COUNT(DISTINCT c.Id) > 0 OR SUM(CASE WHEN v.VoteTypeId IN (2,3,5) THEN 1 ELSE 0 END) > 0
), PostHistoryComplex AS (
    SELECT
        ph.PostId,
        ph.UserId AS HistoryUserId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryDate,
        LEAD(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_history,
        ph.Text AS HistoryText,
        ph.Comment AS HistoryComment,
        CASE
            WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 'Edit'
            WHEN ph.PostHistoryTypeId IN (10, 12) THEN 'Closure/Deletion'
            WHEN ph.PostHistoryTypeId IN (11, 13) THEN 'Reopen/Undeletion'
            ELSE 'Other'
        END AS HistoryCategory
    FROM PostHistory ph
    INNER JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.UserId IS NOT NULL AND ph.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
), PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        tag_name AS TagName,
        t.Count AS TagGlobalCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY t.Count DESC, t.TagName ASC) AS TagRankForPost
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag_name
    ) s
    INNER JOIN Tags t ON s.tag_name = t.TagName
    WHERE p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalQuestions,
    ua.TotalAnswers,
    pe.CommentCount,
    pe.UpVoteCount,
    pe.DownVoteCount,
    pa.Id AS PostId,
    pa.Title,
    pa.CreationDate AS PostCreationDate,
    pa.ViewCount AS PostViewCount,
    pa.Score AS PostScore,
    pa.PostTypeId,
    pt.Name AS PostTypeName,
    phc_latest.HistoryTypeName AS LatestHistoryEvent,
    phc_latest.HistoryDate AS LatestHistoryDate,
    EXTRACT(EPOCH FROM (ua.LastAccessDate - ua.UserCreationDate)) / 86400 AS DaysSinceCreationToLastAccess,
    COALESCE(CASE WHEN (pe.UpVoteCount + pe.DownVoteCount) = 0 THEN 0.0 ELSE CAST(pe.UpVoteCount AS DECIMAL) / (pe.UpVoteCount + pe.DownVoteCount) END, 0.0) AS UpvoteRatio,
    DENSE_RANK() OVER (ORDER BY ua.Reputation DESC, ua.TotalPosts DESC, ua.UserCreationDate ASC) AS UserOverallRank,
    AVG(pe.UpVoteCount) OVER (PARTITION BY pa.PostTypeId) AS AvgUpvotesForPostType,
    MAX(CASE WHEN b.Name LIKE '%Editor%' OR b.Name LIKE '%Reviewer%' THEN 1 ELSE 0 END) OVER (PARTITION BY ua.UserId) AS HasSpecialBadge,
    (SELECT COUNT(DISTINCT ph2.UserId) FROM PostHistory ph2 WHERE ph2.PostId = pa.Id AND ph2.PostHistoryTypeId IN (4,5,6) AND ph2.UserId != pa.OwnerUserId) AS UniqueEditorsCountExcludingOwner,
    LOWER(SUBSTRING(pa.Body FROM 1 FOR 100)) AS BodySnippetLower,
    COALESCE(pe.LinkedPostCount, 0) + COALESCE(pe.DuplicatePostCount, 0) AS TotalRelatedPosts,
    CASE
        WHEN pa.FavoriteCount IS NOT NULL AND pa.FavoriteCount > 0 THEN 'Favorited'
        WHEN pe.UpVoteCount > 10 AND pe.CommentCount > 5 THEN 'Highly Engaged'
        WHEN pa.ViewCount > 5000 AND pa.Score > 20 THEN 'Popular and Valued'
        ELSE 'Standard Engagement'
    END AS EngagementCategory,
    STRING_AGG(pta.TagName, ', ' ORDER BY pta.TagGlobalCount DESC, pta.TagName) FILTER (WHERE pta.TagName IS NOT NULL) AS AllPostTags,
    AVG(EXTRACT(EPOCH FROM (pe.LastCommentDate - pe.FirstCommentDate))) FILTER (WHERE pe.FirstCommentDate IS NOT NULL AND pe.LastCommentDate IS NOT NULL) / 3600 AS AvgCommentThreadHours
FROM UserActivitySummary ua
INNER JOIN Posts pa ON ua.UserId = pa.OwnerUserId
INNER JOIN PostTypes pt ON pa.PostTypeId = pt.Id
LEFT JOIN PostEngagementMetrics pe ON pa.Id = pe.PostId
LEFT JOIN PostHistoryComplex phc_latest ON pa.Id = phc_latest.PostId AND phc_latest.rn_latest_history = 1
LEFT JOIN Badges b ON ua.UserId = b.UserId AND b.Date >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 year')
LEFT JOIN PostTagAnalysis pta ON pa.Id = pta.PostId AND pta.TagRankForPost <= 3
WHERE
    pa.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year')
    AND pa.Score > 5
    AND pa.CommunityOwnedDate IS NULL
    AND (
        (pa.PostTypeId = 1 AND pa.AnswerCount > 0 AND pa.AcceptedAnswerId IS NOT NULL)
        OR (pa.PostTypeId = 2 AND pa.ParentId IS NOT NULL AND pa.CreationDate > (SELECT MIN(p_q.CreationDate) FROM Posts p_q WHERE p_q.Id = pa.ParentId AND p_q.PostTypeId = 1))
    )
    AND (LENGTH(pa.Title) BETWEEN 15 AND 120 OR pa.Title IS NULL)
    AND pa.OwnerDisplayName IS NOT NULL
GROUP BY
    ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalQuestions, ua.TotalAnswers,
    ua.TotalPosts, ua.UserCreationDate, ua.LastAccessDate,
    pe.CommentCount, pe.UpVoteCount, pe.DownVoteCount, pe.LinkedPostCount, pe.DuplicatePostCount, pe.FirstCommentDate, pe.LastCommentDate, pe.FavoriteCount,
    pa.Id, pa.Title, pa.CreationDate, pa.ViewCount, pa.Score, pa.PostTypeId, pa.FavoriteCount, pa.Body, pa.AcceptedAnswerId, pa.OwnerUserId,
    pt.Name, phc_latest.HistoryTypeName, phc_latest.HistoryDate,
    b.Class, b.Name
HAVING
    COUNT(DISTINCT pta.TagName) >= 2
    AND SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) > 0
    AND (SUM(COALESCE(pe.FavoriteCount,0)) > 0 OR SUM(COALESCE(pe.UpVoteCount,0)) > 5)
ORDER BY
    UserOverallRank ASC, pa.CreationDate DESC, pa.Score DESC
LIMIT 250;