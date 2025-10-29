-- {"query": "1160.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3178}
WITH PostMetadata AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.Body,
        p.ClosedDate,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / (3600.0 * 24.0) AS PostAgeDays,
        string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><') AS ParsedTags
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
),
PostActivitySummary AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) AS UniqueEditorsOrModerators,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS DeleteUndeleteCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastClosedDate,
        MIN(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS FirstReopenedDate
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
    GROUP BY
        ph.PostId
),
PostVoteAndCommentMetrics AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        AVG(c.Score) AS AverageCommentScore,
        COUNT(c.Id) AS TotalComments
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    GROUP BY
        p.Id
),
UserEngagementStats AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.CreationDate AS UserCreationDate,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalPostsByOwner,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsByOwner,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersByOwner
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
QuestionDetailedMetrics AS (
    SELECT
        pm.PostId,
        pm.OwnerUserId,
        pm.Title,
        pm.Body,
        pm.CreationDate AS QuestionCreationDate,
        pm.PostAgeDays,
        pm.Score AS InitialScore,
        pm.ViewCount,
        pm.AnswerCount,
        pm.CommentCount AS InitialCommentCount,
        pm.FavoriteCount AS InitialFavoriteCount,
        pm.ParsedTags,
        uas.Reputation AS OwnerReputation,
        uas.UserViews,
        uas.GoldBadges AS OwnerGoldBadges,
        uas.TotalQuestionsByOwner,
        COALESCE(pas.EditCount, 0) AS EditCount,
        COALESCE(pas.CloseEventCount, 0) AS CloseEventCount,
        COALESCE(pas.ReopenEventCount, 0) AS ReopenEventCount,
        COALESCE(pas.DeleteUndeleteCount, 0) AS DeleteUndeleteCount,
        pas.LastClosedDate,
        pas.FirstReopenedDate,
        pvcm.Upvotes,
        pvcm.Downvotes,
        pvcm.Favorites,
        pvcm.TotalComments,
        pvcm.UniqueCommenters,
        pvcm.AverageCommentScore,
        NULLIF(COALESCE(pvcm.Upvotes,0) + COALESCE(pvcm.Downvotes,0), 0) AS TotalVotes,
        (CAST(COALESCE(pvcm.Upvotes,0) AS numeric) - CAST(COALESCE(pvcm.Downvotes,0) AS numeric)) / NULLIF(CAST(COALESCE(pvcm.Upvotes,0) + COALESCE(pvcm.Downvotes,0) AS numeric), 0) AS NetVoteRatio,
        RANK() OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.Score DESC, pm.ViewCount DESC) AS OwnerPostRankByScoreViews,
        LAG(pm.CreationDate, 1) OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.CreationDate) AS PrevQuestionDateByOwner,
        COUNT(pm.PostId) OVER (PARTITION BY pm.OwnerUserId) AS TotalOwnerQuestions,
        (COALESCE(pm.ClosedDate, pas.LastClosedDate) IS NOT NULL) AS IsClosed,
        (LOWER(pm.Title) LIKE '%error%' OR LOWER(pm.Title) LIKE '%bug%') AS HasProblemKeywordInTitle,
        (SELECT EXISTS (
            SELECT 1
            FROM Posts pa
            WHERE pa.ParentId = pm.PostId
              AND pa.Id = (SELECT p_q.AcceptedAnswerId FROM Posts p_q WHERE p_q.Id = pm.PostId)
              AND pa.OwnerUserId IS NOT NULL
        )) AS HasAcceptedAnswerByExistingUser,
        (SELECT EXISTS (
            SELECT 1
            FROM PostHistory ph_editor
            JOIN Badges b_editor ON ph_editor.UserId = b_editor.UserId
            WHERE ph_editor.PostId = pm.PostId
              AND ph_editor.PostHistoryTypeId IN (4, 5, 6)
              AND b_editor.Class = 1
              AND b_editor.TagBased = TRUE
              AND b_editor.Name IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM unnest(pm.ParsedTags) AS post_tag WHERE post_tag = b_editor.Name
              )
        )) AS EditedByTagGoldBadger
    FROM
        PostMetadata pm
    LEFT JOIN
        PostActivitySummary pas ON pm.PostId = pas.PostId
    LEFT JOIN
        PostVoteAndCommentMetrics pvcm ON pm.PostId = pvcm.PostId
    LEFT JOIN
        UserEngagementStats uas ON pm.OwnerUserId = uas.UserId
    WHERE
        pm.OwnerUserId IS NOT NULL
        AND uas.Reputation > 500
        AND LENGTH(pm.Body) > 500
        AND pm.ParsedTags IS NOT NULL
        AND array_length(pm.ParsedTags, 1) > 0
)
SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.OwnerReputation,
    q.QuestionCreationDate,
    q.PostAgeDays,
    q.Upvotes,
    q.Downvotes,
    q.Favorites,
    q.TotalComments,
    q.EditCount,
    q.CloseEventCount,
    q.ReopenEventCount,
    q.NetVoteRatio,
    q.IsClosed,
    q.HasProblemKeywordInTitle,
    q.ParsedTags,
    q.OwnerPostRankByScoreViews,
    (q.TotalOwnerQuestions > 1 AND AGE(q.QuestionCreationDate, q.PrevQuestionDateByOwner) < INTERVAL '30 days') AS OwnerFrequentPoster,
    q.HasAcceptedAnswerByExistingUser,
    q.EditedByTagGoldBadger,
    'Highly Edited/Moderated' AS QuestionHighlightType,
    AVG(q.EditCount) OVER (PARTITION BY floor(q.OwnerReputation / 5000) * 5000) AS AvgEditCountByHighRepRange,
    COALESCE(
        LEFT(q.Title, POSITION(' ' IN q.Title) - 1),
        q.Title,
        'NoTitle'
    ) AS FirstWordInTitle
FROM
    QuestionDetailedMetrics q
WHERE
    q.PostAgeDays > 60
    AND q.TotalComments > 10
    AND q.EditCount > 5
    AND (q.CloseEventCount > 0 OR q.ReopenEventCount > 0)
    AND q.OwnerReputation > 1000
    AND q.EditedByTagGoldBadger = TRUE
UNION ALL
SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.OwnerReputation,
    q.QuestionCreationDate,
    q.PostAgeDays,
    q.Upvotes,
    q.Downvotes,
    q.Favorites,
    q.TotalComments,
    q.EditCount,
    q.CloseEventCount,
    q.ReopenEventCount,
    q.NetVoteRatio,
    q.IsClosed,
    q.HasProblemKeywordInTitle,
    q.ParsedTags,
    q.OwnerPostRankByScoreViews,
    (q.TotalOwnerQuestions > 1 AND AGE(q.QuestionCreationDate, q.PrevQuestionDateByOwner) < INTERVAL '30 days') AS OwnerFrequentPoster,
    q.HasAcceptedAnswerByExistingUser,
    q.EditedByTagGoldBadger,
    'Highly Voted/Controversial' AS QuestionHighlightType,
    AVG(q.NetVoteRatio) OVER (PARTITION BY q.HasProblemKeywordInTitle) AS AvgNetVoteRatioByProblematicTitle,
    COALESCE(
        LEFT(q.Title, POSITION(' ' IN q.Title) - 1),
        q.Title,
        'NoTitle'
    ) AS FirstWordInTitle
FROM
    QuestionDetailedMetrics q
WHERE
    q.PostAgeDays > 30
    AND q.Upvotes > 100
    AND q.Downvotes > 10
    AND (q.NetVoteRatio < 0.7 OR q.Favorites > 20)
    AND q.HasAcceptedAnswerByExistingUser = TRUE
    AND q.OwnerReputation > 750
ORDER BY
    QuestionCreationDate DESC, Upvotes DESC
LIMIT 2000;