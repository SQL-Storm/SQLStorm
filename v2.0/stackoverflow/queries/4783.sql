-- {"query": "4783.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 986}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.CreationDate AS EditDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditCounts AS (
    SELECT
        PostId,
        COUNT(DISTINCT UserId) AS DistinctEditors,
        SUM(CASE WHEN rn = 1 THEN 1 ELSE 0 END) AS LastEditorCount -- Count of users who made the most recent edit to a post
    FROM RankedPostEdits
    GROUP BY PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreFromPosts,
        AVG(p.AnswerCount) AS AvgAnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(DISTINCT c.PostId) AS DistinctPostsCommentedOn
    FROM Comments c
    WHERE c.UserId IS NOT NULL AND c.UserId > 0
    GROUP BY c.UserId
),
RecentQuestions AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        CreationDate,
        Tags,
        ROW_NUMBER() OVER(ORDER BY CreationDate DESC) as rn
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 days')
)
SELECT
    rq.Title AS QuestionTitle,
    rq.CreationDate AS QuestionCreationDate,
    upc.TotalPostsOwned AS OwnerTotalPosts,
    upc.TotalScoreFromPosts AS OwnerTotalScore,
    COALESCE(pec.DistinctEditors, 0) AS DistinctEditorsForThisPost,
    COALESCE(pec.LastEditorCount, 0) AS LastEditorMadeThisEdit,
    ua.TotalCommentsMade AS OwnerTotalComments,
    ua.TotalCommentScore AS OwnerTotalCommentScore,
    CASE
        WHEN rq.Tags LIKE '%<sql>%' THEN 'SQL Related'
        WHEN rq.Tags LIKE '%<performance>%' THEN 'Performance Related'
        ELSE 'Other'
    END AS TagCategory,
    UPPER(SUBSTRING(rq.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE
        WHEN rq.OwnerUserId IS NULL OR rq.OwnerUserId = -1 THEN 'Community'
        ELSE COALESCE(u.DisplayName, 'Unknown')
    END AS OwnerDisplayName,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rq.Id AND pl.LinkTypeId = 3) AS DuplicateLinksCount,
    (
        SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
        FROM Votes v
        WHERE v.PostId = rq.Id
    ) AS UpvoteCountForQuestion,
    CASE
        WHEN EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = rq.Id AND c.Score > 5) THEN 'Highly Scored Comments Exist'
        ELSE 'No Highly Scored Comments'
    END AS CommentScoreIndicator
FROM
    RecentQuestions rq
LEFT JOIN
    UserPostActivity upc ON rq.OwnerUserId = upc.OwnerUserId
LEFT JOIN
    PostEditCounts pec ON rq.Id = pec.PostId
LEFT JOIN
    UserCommentActivity ua ON rq.OwnerUserId = ua.UserId
LEFT JOIN
    Users u ON rq.OwnerUserId = u.Id
WHERE
    rq.rn <= 50
    AND COALESCE(pec.DistinctEditors, 0) > 1 -- Only consider questions with more than one editor
    AND COALESCE(upc.TotalPostsOwned, 0) > 10 -- Owner has at least 10 posts
    AND COALESCE(ua.TotalCommentScore, 0) > 100 -- Owner has a decent comment score
ORDER BY
    rq.CreationDate DESC, COALESCE(upc.TotalScoreFromPosts, 0) DESC;