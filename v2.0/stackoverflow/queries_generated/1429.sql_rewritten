-- {"query": "1429.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3844} 
WITH RecentHighRepUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        CASE
            WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN 'Unknown_Location'
            WHEN LENGTH(TRIM(u.Location)) > 50 THEN TRIM(SUBSTRING(u.Location FROM 1 FOR 50)) || '...'
            ELSE TRIM(u.Location)
        END AS UserLocationClean,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation >= 10000
        AND u.LastAccessDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
        AND u.CreationDate <= cast('2024-10-01' as date) - INTERVAL '2 years'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes, u.Location
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.AcceptedAnswerId,
        LOWER(COALESCE(p.OwnerDisplayName, 'community_wiki_post')) AS OwnerDisplayNameLower,
        -- Extract tags, handle NULLs and empty strings. Tags column format: <tag1><tag2>
        CASE
            WHEN p.Tags IS NULL OR TRIM(p.Tags) = '' THEN NULL
            ELSE string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')
        END AS TagArray,
        -- Correlated subquery to find last editor's reputation if available
        (
            SELECT COALESCE(MAX(leu.Reputation), 0)
            FROM Users leu
            WHERE leu.Id = p.LastEditorUserId
        ) AS LastEditorReputation
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only questions
),
AggregatedCommentScores AS (
    SELECT
        c.PostId,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(c.Id) AS TotalComments,
        COUNT(DISTINCT c.UserId) AS DistinctCommenters,
        -- Check for comments made by the post owner (handle NULL UserId for anonymous comments)
        SUM(CASE WHEN c.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnerComments
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id -- Join to get Post.OwnerUserId for correlation
    WHERE c.CreationDate >= cast('2024-10-01' as date) - INTERVAL '3 months'
    GROUP BY c.PostId, p.OwnerUserId
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edit
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes,
        MAX(ph.CreationDate) AS LastHistoryActivityDate,
        -- Complicated predicate/expression within a CTE: count distinct users who edited or closed a post
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6,10) AND ph.UserId IS NOT NULL THEN ph.UserId END) AS DistinctActionUsers,
        MAX(CASE
                WHEN ph.PostHistoryTypeId = 10 THEN COALESCE(ph.Comment, 'No_Close_Reason')
                ELSE NULL
            END) AS LastCloseReasonComment,
        MAX(CASE
                WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) AND ph.Text IS NOT NULL
                THEN SUBSTRING(ph.Text FROM 1 FOR 100) || '...'
                ELSE NULL
            END) AS HistoryTextSnippet
    FROM PostHistory ph
    WHERE ph.CreationDate >= cast('2024-10-01' as date) - INTERVAL '2 years'
    GROUP BY ph.PostId
),
VoteAnalysis AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountyGiven,
        SUM(CASE WHEN v.VoteTypeId = 9 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountyReceived,
        COUNT(DISTINCT v.UserId) AS DistinctVoters
    FROM Votes v
    WHERE v.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
    GROUP BY v.PostId
)
-- Main Query for highly engaged questions
SELECT
    'Question' AS PostCategory,
    rhu.UserId,
    rhu.UserName,
    rhu.Reputation,
    rhu.UserLocationClean,
    rhu.GoldBadges,
    rhu.SilverBadges,
    rhu.BronzeBadges,
    pta.PostId,
    pta.Title AS PostTitle,
    pta.Score AS PostScore,
    pta.ViewCount AS PostViewCount,
    pta.AnswerCount,
    pta.CommentCount AS PostBuiltinCommentCount, -- From Posts table
    COALESCE(acs.TotalComments, 0) AS AggregatedCommentTotal, -- From Comments table
    COALESCE(acs.TotalCommentScore, 0) AS AggregatedCommentScore,
    COALESCE(acs.DistinctCommenters, 0) AS AggregatedDistinctCommenters,
    COALESCE(acs.OwnerComments, 0) AS AggregatedOwnerComments,
    phd.EditCount,
    phd.CloseVotes,
    phd.ReopenVotes,
    phd.LastCloseReasonComment,
    phd.HistoryTextSnippet,
    va.UpVotes AS PostUpVotes,
    va.DownVotes AS PostDownVotes,
    va.AcceptedAnswers,
    va.TotalBountyGiven,
    va.TotalBountyReceived,
    va.DistinctVoters,
    pta.LastEditorReputation,
    pta.PostCreationDate,
    pta.LastEditDate,
    pta.LastActivityDate,
    pta.ClosedDate,
    -- String manipulation and NULL logic
    COALESCE(REPLACE(pta.OwnerDisplayNameLower, ' ', '_'), 'community_user') AS NormalizedOwnerDisplayName,
    -- Conditional expressions with CASE
    CASE
        WHEN pta.AcceptedAnswerId IS NOT NULL AND COALESCE(pta.AnswerCount, 0) > 0 THEN 'Solved_And_Answered'
        WHEN COALESCE(pta.AnswerCount, 0) > 0 THEN 'Answered_But_Unaccepted'
        WHEN pta.ClosedDate IS NOT NULL THEN 'Closed_Question'
        ELSE 'Open_Question'
    END AS QuestionStatus,
    -- Complex calculation: Days since last activity vs creation and activity rate
    EXTRACT(DAY FROM (cast('2024-10-01' as date) - pta.PostCreationDate)) AS DaysSinceCreation,
    EXTRACT(DAY FROM (cast('2024-10-01' as date) - pta.LastActivityDate)) AS DaysSinceLastActivity,
    (pta.Score * 1.0 / GREATEST(1, EXTRACT(DAY FROM (cast('2024-10-01' as date) - pta.PostCreationDate)))) AS ScorePerDayLife,
    -- Window functions
    RANK() OVER (PARTITION BY rhu.UserId ORDER BY pta.Score DESC, pta.ViewCount DESC) AS RankByUserScore,
    AVG(pta.Score) OVER (PARTITION BY rhu.UserLocationClean) AS AvgScoreInUserLocation,
    tag_unnested.Tag AS TagName,
    COUNT(tag_unnested.Tag) OVER (PARTITION BY tag_unnested.Tag) AS TotalPostsWithTag,
    AVG(pta.Score) OVER (PARTITION BY tag_unnested.Tag) AS AvgScoreForTag,
    -- Another correlated subquery example for PostLinks (duplicates)
    (
        SELECT COUNT(pl.Id)
        FROM PostLinks pl
        WHERE pl.PostId = pta.PostId AND pl.LinkTypeId = 3 -- Duplicate links
    ) AS DuplicateLinkCount,
    -- Another correlated subquery example for PostLinks (linked)
    (
        SELECT COUNT(pl.Id)
        FROM PostLinks pl
        WHERE pl.RelatedPostId = pta.PostId AND pl.LinkTypeId = 1 -- Linked FROM this post
    ) AS LinkedFromOtherPostsCount,
    LAG(pta.Score, 1, 0) OVER (PARTITION BY rhu.UserId ORDER BY pta.PostCreationDate) AS PreviousPostScore
FROM RecentHighRepUsers rhu
JOIN PostTagAnalysis pta ON rhu.UserId = pta.OwnerUserId
LEFT JOIN AggregatedCommentScores acs ON pta.PostId = acs.PostId
LEFT JOIN PostHistoryDetails phd ON pta.PostId = phd.PostId
LEFT JOIN VoteAnalysis va ON pta.PostId = va.PostId
LEFT JOIN LATERAL UNNEST(pta.TagArray) AS tag_unnested(Tag) ON TRUE -- Unnest tags for each question
WHERE
    pta.ViewCount > 10000
    AND pta.Score > 100
    AND pta.LastActivityDate >= cast('2024-10-01' as date) - INTERVAL '6 months'
    AND rhu.TotalBadges >= 75
    AND pta.TagArray IS NOT NULL -- Ensure tags exist for unnesting
    AND (pta.ClosedDate IS NULL OR pta.ClosedDate > cast('2024-10-01' as date) - INTERVAL '1 year') -- Not too old closed posts
    AND pta.LastEditorReputation > 5000 -- Only posts with an editor having significant reputation
    AND COALESCE(acs.TotalComments, 0) > 10 -- Posts with significant comment activity
    AND COALESCE(va.UpVotes, 0) > COALESCE(va.DownVotes, 0) * 3 -- Upvotes significantly outnumber downvotes
    AND tag_unnested.Tag ILIKE '%performance%' -- Filter for specific tags (case-insensitive)
    AND phd.EditCount > 2
-- UNION ALL with a different selection criteria, e.g., highly upvoted answers
UNION ALL
SELECT
    'Answer' AS PostCategory,
    rhu.UserId,
    rhu.UserName,
    rhu.Reputation,
    rhu.UserLocationClean,
    rhu.GoldBadges,
    rhu.SilverBadges,
    rhu.BronzeBadges,
    p_ans.Id AS PostId,
    qp.Title AS PostTitle, -- Title of the parent question for an answer
    p_ans.Score AS PostScore,
    NULL AS PostViewCount, -- Not directly applicable for answers
    NULL AS AnswerCount, -- Not applicable for answers
    p_ans.CommentCount AS PostBuiltinCommentCount,
    COALESCE(acs_ans.TotalComments, 0) AS AggregatedCommentTotal,
    COALESCE(acs_ans.TotalCommentScore, 0) AS AggregatedCommentScore,
    COALESCE(acs_ans.DistinctCommenters, 0) AS AggregatedDistinctCommenters,
    COALESCE(acs_ans.OwnerComments, 0) AS AggregatedOwnerComments,
    phd_ans.EditCount,
    COALESCE(phd_ans.CloseVotes, 0) AS CloseVotes, -- Not typically relevant for answers, will be 0
    COALESCE(phd_ans.ReopenVotes, 0) AS ReopenVotes, -- Not typically relevant for answers, will be 0
    phd_ans.LastCloseReasonComment,
    phd_ans.HistoryTextSnippet,
    va_ans.UpVotes AS PostUpVotes,
    va_ans.DownVotes AS PostDownVotes,
    COALESCE(va_ans.AcceptedAnswers, 0) AS AcceptedAnswers, -- Will be 0 for answers
    COALESCE(va_ans.TotalBountyGiven, 0) AS TotalBountyGiven,
    COALESCE(va_ans.TotalBountyReceived, 0) AS TotalBountyReceived,
    COALESCE(va_ans.DistinctVoters, 0) AS DistinctVoters,
    (
        SELECT COALESCE(MAX(leu.Reputation), 0)
        FROM Users leu
        WHERE leu.Id = p_ans.LastEditorUserId
    ) AS LastEditorReputation, -- Correlated subquery for answers
    p_ans.CreationDate AS PostCreationDate,
    p_ans.LastEditDate,
    p_ans.LastActivityDate,
    p_ans.ClosedDate, -- Not typically relevant for answers
    COALESCE(REPLACE(LOWER(p_ans.OwnerDisplayName), ' ', '_'), 'community_user') AS NormalizedOwnerDisplayName,
    'Answer' AS QuestionStatus, -- Simplified status for answers
    EXTRACT(DAY FROM (cast('2024-10-01' as date) - p_ans.CreationDate)) AS DaysSinceCreation,
    EXTRACT(DAY FROM (cast('2024-10-01' as date) - p_ans.LastActivityDate)) AS DaysSinceLastActivity,
    (p_ans.Score * 1.0 / GREATEST(1, EXTRACT(DAY FROM (cast('2024-10-01' as date) - p_ans.CreationDate)))) AS ScorePerDayLife,
    RANK() OVER (PARTITION BY rhu.UserId ORDER BY p_ans.Score DESC) AS RankByUserScore,
    AVG(p_ans.Score) OVER (PARTITION BY rhu.UserLocationClean) AS AvgScoreInUserLocation,
    'N/A_Answer_Tag' AS TagName, -- Tags are primarily for questions
    NULL AS TotalPostsWithTag,
    NULL AS AvgScoreForTag,
    0 AS DuplicateLinkCount, -- Not typically applicable for answers
    0 AS LinkedFromOtherPostsCount, -- Not typically applicable for answers
    LAG(p_ans.Score, 1, 0) OVER (PARTITION BY rhu.UserId ORDER BY p_ans.CreationDate) AS PreviousPostScore
FROM RecentHighRepUsers rhu
JOIN Posts p_ans ON rhu.UserId = p_ans.OwnerUserId
JOIN Posts qp ON p_ans.ParentId = qp.Id -- Join to get the parent question for context
LEFT JOIN AggregatedCommentScores acs_ans ON p_ans.Id = acs_ans.PostId
LEFT JOIN PostHistoryDetails phd_ans ON p_ans.Id = phd_ans.PostId
LEFT JOIN VoteAnalysis va_ans ON p_ans.Id = va_ans.PostId
WHERE
    p_ans.PostTypeId = 2 -- Only answers
    AND p_ans.Score > 500 -- Highly upvoted answers
    AND p_ans.CreationDate >= cast('2024-10-01' as date) - INTERVAL '3 years'
    AND rhu.Reputation > 75000 -- Even higher reputation for answerers
    AND qp.ViewCount > 100000 -- Answer to a very popular question
    AND COALESCE(phd_ans.EditCount, 0) >= 1 -- Answer has been edited at least once
    AND p_ans.OwnerDisplayName IS NOT NULL
ORDER BY Reputation DESC, PostScore DESC, PostViewCount DESC NULLS LAST;