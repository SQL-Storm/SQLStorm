-- {"query": "1159.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3691} 

WITH PostEditSummary AS (
    -- Summarizes editing activity for each post
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate,
        -- Flags for specific history events
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (11, 22) THEN 1 ELSE 0 END) AS WasReopened
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (
        4, 5, 6, -- Post edits (Title, Body, Tags)
        10, 11, 12, 13, 22, -- Closure, Reopen, Delete, Undelete, Question Unmerged
        101, 102, 103, 104, 105 -- Current close reasons
    )
    GROUP BY ph.PostId
),
PostVoteCommentSummary AS (
    -- Aggregates vote and comment data for each post
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(COALESCE(c.Score, 0)) AS AvgCommentScore,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount -- Favorite (bookmark) votes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
PostLinkage AS (
    -- Identifies linked and duplicate posts
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedFromCount, -- Posts linking to this one
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateOfCount -- This post is a duplicate of another
    FROM PostLinks pl
    GROUP BY pl.PostId
),
UserBadgeCounts AS (
    -- Counts the number of Gold, Silver, and Bronze badges for each user
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Badges
    GROUP BY UserId
)
-- Main query: Analyze posts based on their content, engagement, evolution, and associated user influence.
-- Part 1: Focus on active, well-engaged questions and answers
SELECT
    P.Id AS PostId,
    P.PostTypeId,
    PT.Name AS PostTypeName,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount,
    P.Title,
    P.Tags,
    U_Owner.Id AS OwnerUserId,
    U_Owner.DisplayName AS OwnerDisplayName,
    U_Owner.Reputation AS OwnerReputation,
    U_LastEditor.DisplayName AS LastEditorDisplayName,
    COALESCE(PES.EditCount, 0) AS EditCount,
    COALESCE(PES.DistinctEditors, 0) AS DistinctEditors,
    (PES.LastEditDate - PES.FirstEditDate) AS TimeSpanFirstLastEdit, -- Interval between first and last edit
    COALESCE(PVCS.UpVoteCount, 0) AS PostUpVotes,
    COALESCE(PVCS.DownVoteCount, 0) AS PostDownVotes,
    COALESCE(PVCS.CommentCount, 0) AS PostCommentCount,
    COALESCE(PVCS.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(PVCS.FavoriteCount, 0) AS FavoriteCount,
    COALESCE(PL.LinkedFromCount, 0) AS LinkedPostCount,
    COALESCE(PL.DuplicateOfCount, 0) AS DuplicatePostCount,
    COALESCE(P.AnswerCount, 0) AS AnswerCount,

    -- Complicated calculation: "Engagement to View Ratio"
    CAST(COALESCE(PVCS.UpVoteCount + PVCS.CommentCount + (2 * PVCS.FavoriteCount), 0) AS NUMERIC) / NULLIF(P.ViewCount, 0) AS EngagementToViewRatio,

    -- String manipulation and NULL logic on Tags for categorization
    CASE
        WHEN P.Tags IS NULL THEN 'No Tags'
        WHEN P.Tags LIKE '%<sql>%' AND P.Tags LIKE '%<database>%' THEN 'SQL & Database Focused'
        WHEN P.Tags LIKE '%<python>%' OR P.Tags LIKE '%<javascript>%' THEN 'Scripting Language'
        WHEN P.Tags LIKE '%<c#>%<.net>%' THEN 'Microsoft Ecosystem'
        ELSE 'Other/General Tech'
    END AS TagCategory,

    -- Correlated Subquery: Average score of answers to this question by high-reputation users, posted within 30 days
    (SELECT AVG(SA.Score)
     FROM Posts SA
     JOIN Users SU ON SA.OwnerUserId = SU.Id
     WHERE SA.ParentId = P.Id
       AND SA.PostTypeId = 2 -- Only consider answers
       AND SU.Reputation >= 5000 -- Only answers from high-reputation users
       AND SA.CreationDate < P.CreationDate + INTERVAL '30 days' -- Answer within 30 days of question
    ) AS AvgHighRepAnswerScore30Days,

    -- Window Function: Rank posts by a composite engagement score within their type
    RANK() OVER (PARTITION BY P.PostTypeId ORDER BY (P.Score * 0.5 + COALESCE(PVCS.UpVoteCount,0) * 0.3 + COALESCE(PVCS.CommentCount,0) * 0.2) DESC, P.CreationDate DESC) AS EngagementRankByType,

    -- Window Function: Calculate the average view count for posts by the same owner in a rolling 6-month window
    AVG(P.ViewCount) OVER (
        PARTITION BY P.OwnerUserId
        ORDER BY P.CreationDate
        RANGE BETWEEN INTERVAL '6 months' PRECEDING AND CURRENT ROW
    ) AS AvgOwnerViewCountLast6Months,

    -- Window Function: Time difference (interval) to the previous post by the same owner
    P.CreationDate - LAG(P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS TimeSincePrevPostByOwner,

    -- Complex Predicate / NULL logic to determine Post Status
    CASE
        WHEN P.ClosedDate IS NOT NULL AND COALESCE(PES.WasReopened, 0) = 1 THEN 'Closed & Reopened'
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN P.PostTypeId = 1 AND COALESCE(P.AnswerCount, 0) = 0 AND P.CreationDate < NOW() - INTERVAL '1 year' THEN 'Stale Question No Answer'
        ELSE 'Open & Active'
    END AS PostStatus,

    -- String expression and NULL check on Body for snippet and code detection
    COALESCE(SUBSTRING(P.Body, 1, 150), 'No Body Content Available') AS BodySnippet,
    P.Body LIKE '%<code>%' AS ContainsCodeSnippet,
    (LENGTH(COALESCE(P.Title, '')) + LENGTH(COALESCE(P.Body, ''))) AS TotalContentLength,

    -- Join in user badge counts for the post owner
    COALESCE(UBC.GoldBadgeCount, 0) AS OwnerGoldBadges,
    COALESCE(UBC.SilverBadgeCount, 0) AS OwnerSilverBadges,
    COALESCE(UBC.BronzeBadgeCount, 0) AS OwnerBronzeBadges

FROM Posts P
JOIN PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN Users U_Owner ON P.OwnerUserId = U_Owner.Id
LEFT JOIN Users U_LastEditor ON P.LastEditorUserId = U_LastEditor.Id
LEFT JOIN PostEditSummary PES ON P.Id = PES.PostId
LEFT JOIN PostVoteCommentSummary PVCS ON P.Id = PVCS.PostId
LEFT JOIN PostLinkage PL ON P.Id = PL.PostId
LEFT JOIN UserBadgeCounts UBC ON U_Owner.Id = UBC.UserId

WHERE
    P.CreationDate >= '2020-01-01' -- Filter for recent data
    AND P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
    AND P.Score >= 0 -- Exclude negatively scored initial posts for this analysis
    AND P.Body IS NOT NULL -- Ensure body content exists for analysis
    AND (P.ViewCount > 1000 OR COALESCE(PVCS.FavoriteCount, 0) > 5) -- Filter for more engaged posts
    AND U_Owner.Reputation > 500 -- Only posts from moderately reputable users
    AND P.OwnerUserId IS NOT NULL -- Ensure owner exists for user-based calculations

-- Set operator: UNION ALL to combine with a different data slice - posts that were closed, deleted, or migrated
UNION ALL

-- Part 2: Focus on posts with specific historical events (deleted, migrated, or closed with specific reasons)
SELECT
    P.Id AS PostId,
    P.PostTypeId,
    PT.Name AS PostTypeName,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount,
    P.Title,
    P.Tags,
    U_Owner.Id AS OwnerUserId,
    U_Owner.DisplayName AS OwnerDisplayName,
    U_Owner.Reputation AS OwnerReputation,
    U_LastEditor.DisplayName AS LastEditorDisplayName,
    COALESCE(PES.EditCount, 0) AS EditCount,
    COALESCE(PES.DistinctEditors, 0) AS DistinctEditors,
    (PES.LastEditDate - PES.FirstEditDate) AS TimeSpanFirstLastEdit,
    COALESCE(PVCS.UpVoteCount, 0) AS PostUpVotes,
    COALESCE(PVCS.DownVoteCount, 0) AS PostDownVotes,
    COALESCE(PVCS.CommentCount, 0) AS PostCommentCount,
    COALESCE(PVCS.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(PVCS.FavoriteCount, 0) AS FavoriteCount,
    COALESCE(PL.LinkedFromCount, 0) AS LinkedPostCount,
    COALESCE(PL.DuplicateOfCount, 0) AS DuplicatePostCount,
    COALESCE(P.AnswerCount, 0) AS AnswerCount,

    CAST(COALESCE(PVCS.UpVoteCount + PVCS.CommentCount + (2 * PVCS.FavoriteCount), 0) AS NUMERIC) / NULLIF(P.ViewCount, 0) AS EngagementToViewRatio,
    CASE
        WHEN P.Tags IS NULL THEN 'No Tags'
        WHEN P.Tags LIKE '%<sql>%' AND P.Tags LIKE '%<database>%' THEN 'SQL & Database Focused'
        WHEN P.Tags LIKE '%<python>%' OR P.Tags LIKE '%<javascript>%' THEN 'Scripting Language'
        WHEN P.Tags LIKE '%<c#>%<.net>%' THEN 'Microsoft Ecosystem'
        ELSE 'Other/General Tech'
    END AS TagCategory,

    -- Correlated Subquery (same logic as in Part 1 for consistency)
    (SELECT AVG(SA.Score)
     FROM Posts SA
     JOIN Users SU ON SA.OwnerUserId = SU.Id
     WHERE SA.ParentId = P.Id
       AND SA.PostTypeId = 2
       AND SU.Reputation >= 5000
       AND SA.CreationDate < P.CreationDate + INTERVAL '30 days'
    ) AS AvgHighRepAnswerScore30Days,

    -- Window Function (same logic as in Part 1 for consistency)
    RANK() OVER (PARTITION BY P.PostTypeId ORDER BY (P.Score * 0.5 + COALESCE(PVCS.UpVoteCount,0) * 0.3 + COALESCE(PVCS.CommentCount,0) * 0.2) DESC, P.CreationDate DESC) AS EngagementRankByType,

    -- Window Function (same logic as in Part 1 for consistency)
    AVG(P.ViewCount) OVER (
        PARTITION BY P.OwnerUserId
        ORDER BY P.CreationDate
        RANGE BETWEEN INTERVAL '6 months' PRECEDING AND CURRENT ROW
    ) AS AvgOwnerViewCountLast6Months,

    -- Window Function (same logic as in Part 1 for consistency)
    P.CreationDate - LAG(P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS TimeSincePrevPostByOwner,

    -- Specialized Post Status for the UNION ALL part, including close reason details
    CASE
        WHEN PH.PostHistoryTypeId = 12 THEN 'Explicitly Deleted'
        WHEN PH.PostHistoryTypeId = 35 THEN 'Migrated Away'
        WHEN PH.PostHistoryTypeId = 36 THEN 'Migrated Here'
        WHEN PH.PostHistoryTypeId = 10 AND CR.Name IS NOT NULL THEN 'Closed: ' || CR.Name -- Detailed close reason
        ELSE 'Other Special Event' -- Should be covered by WHERE clause filters
    END AS PostStatus,

    COALESCE(SUBSTRING(P.Body, 1, 150), 'No Body Content Available') AS BodySnippet,
    P.Body LIKE '%<code>%' AS ContainsCodeSnippet,
    (LENGTH(COALESCE(P.Title, '')) + LENGTH(COALESCE(P.Body, ''))) AS TotalContentLength,

    COALESCE(UBC.GoldBadgeCount, 0) AS OwnerGoldBadges,
    COALESCE(UBC.SilverBadgeCount, 0) AS OwnerSilverBadges,
    COALESCE(UBC.BronzeBadgeCount, 0) AS OwnerBronzeBadges

FROM Posts P
JOIN PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN Users U_Owner ON P.OwnerUserId = U_Owner.Id
LEFT JOIN Users U_LastEditor ON P.LastEditorUserId = U_LastEditor.Id
LEFT JOIN PostEditSummary PES ON P.Id = PES.PostId
LEFT JOIN PostVoteCommentSummary PVCS ON P.Id = PVCS.PostId
LEFT JOIN PostLinkage PL ON P.Id = PL.PostId
LEFT JOIN UserBadgeCounts UBC ON U_Owner.Id = UBC.UserId
JOIN PostHistory PH ON P.Id = PH.PostId -- Explicit join to PostHistory to filter for specific events
LEFT JOIN CloseReasonTypes CR ON (PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) AND PH.Comment = CR.Id::varchar) -- Join for close reason names

WHERE
    PH.PostHistoryTypeId IN (10, 12, 35, 36) -- Posts that were closed, deleted, or migrated
    AND P.CreationDate >= '2020-01-01'
    AND P.OwnerUserId IS NOT NULL
    AND U_Owner.Reputation < 1000 -- Focus on posts from users with less reputation for this segment
;
