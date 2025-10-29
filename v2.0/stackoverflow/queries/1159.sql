-- {"query": "1159.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3691}
WITH PostEditSummary AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (11, 22) THEN 1 ELSE 0 END) AS WasReopened
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (
        4, 5, 6,
        10, 11, 12, 13, 22,
        101, 102, 103, 104, 105
    )
    GROUP BY ph.PostId
),
PostVoteCommentSummary AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(COALESCE(c.Score, 0)) AS AvgCommentScore,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
PostLinkage AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedFromCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateOfCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
UserBadgeCounts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Badges
    GROUP BY UserId
)

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
    (SELECT AVG(SA.Score)
     FROM Posts SA
     JOIN Users SU ON SA.OwnerUserId = SU.Id
     WHERE SA.ParentId = P.Id
       AND SA.PostTypeId = 2
       AND SU.Reputation >= 5000
       AND SA.CreationDate < P.CreationDate + INTERVAL '30 days'
    ) AS AvgHighRepAnswerScore30Days,
    RANK() OVER (
        PARTITION BY P.PostTypeId
        ORDER BY (P.Score * 0.5 + COALESCE(PVCS.UpVoteCount,0) * 0.3 + COALESCE(PVCS.CommentCount,0) * 0.2) DESC,
                 P.CreationDate DESC
    ) AS EngagementRankByType,
    AVG(P.ViewCount) OVER (
        PARTITION BY P.OwnerUserId
        ORDER BY P.CreationDate
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS AvgOwnerViewCountLast6Months,
    P.CreationDate - LAG(P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS TimeSincePrevPostByOwner,
    CASE
        WHEN P.ClosedDate IS NOT NULL AND COALESCE(PES.WasReopened, 0) = 1 THEN 'Closed & Reopened'
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN P.PostTypeId = 1 AND COALESCE(P.AnswerCount, 0) = 0 AND P.CreationDate < CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year' THEN 'Stale Question No Answer'
        ELSE 'Open & Active'
    END AS PostStatus,
    COALESCE(SUBSTRING(P.Body FROM 1 FOR 150), 'No Body Content Available') AS BodySnippet,
    (P.Body LIKE '%<code>%') AS ContainsCodeSnippet,
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

WHERE
    P.CreationDate >= DATE '2020-01-01'
    AND P.PostTypeId IN (1, 2)
    AND P.Score >= 0
    AND P.Body IS NOT NULL
    AND (P.ViewCount > 1000 OR COALESCE(PVCS.FavoriteCount, 0) > 5)
    AND U_Owner.Reputation > 500
    AND P.OwnerUserId IS NOT NULL

UNION ALL

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
    (SELECT AVG(SA.Score)
     FROM Posts SA
     JOIN Users SU ON SA.OwnerUserId = SU.Id
     WHERE SA.ParentId = P.Id
       AND SA.PostTypeId = 2
       AND SU.Reputation >= 5000
       AND SA.CreationDate < P.CreationDate + INTERVAL '30 days'
    ) AS AvgHighRepAnswerScore30Days,
    RANK() OVER (
        PARTITION BY P.PostTypeId
        ORDER BY (P.Score * 0.5 + COALESCE(PVCS.UpVoteCount,0) * 0.3 + COALESCE(PVCS.CommentCount,0) * 0.2) DESC,
                 P.CreationDate DESC
    ) AS EngagementRankByType,
    AVG(P.ViewCount) OVER (
        PARTITION BY P.OwnerUserId
        ORDER BY P.CreationDate
        RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS AvgOwnerViewCountLast6Months,
    P.CreationDate - LAG(P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS TimeSincePrevPostByOwner,
    CASE
        WHEN PH.PostHistoryTypeId = 12 THEN 'Explicitly Deleted'
        WHEN PH.PostHistoryTypeId = 35 THEN 'Migrated Away'
        WHEN PH.PostHistoryTypeId = 36 THEN 'Migrated Here'
        WHEN PH.PostHistoryTypeId = 10 AND CR.Name IS NOT NULL THEN 'Closed: ' || CR.Name
        ELSE 'Other Special Event'
    END AS PostStatus,
    COALESCE(SUBSTRING(P.Body FROM 1 FOR 150), 'No Body Content Available') AS BodySnippet,
    (P.Body LIKE '%<code>%') AS ContainsCodeSnippet,
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
JOIN PostHistory PH ON P.Id = PH.PostId
LEFT JOIN CloseReasonTypes CR ON (PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) AND PH.Comment = CAST(CR.Id AS varchar))

WHERE
    PH.PostHistoryTypeId IN (10, 12, 35, 36)
    AND P.CreationDate >= DATE '2020-01-01'
    AND P.OwnerUserId IS NOT NULL
    AND U_Owner.Reputation < 1000
;