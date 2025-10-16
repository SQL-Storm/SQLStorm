WITH ActiveUsers AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS ReputationRank,
        u.LastAccessDate
    FROM Users u
    WHERE u.Reputation > 100
      AND u.LastAccessDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
),
QuestionMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        au.Id AS OwnerId,
        au.ReputationRank,
        COALESCE(accepted.Score, 0) AS AcceptedScore,
        LAG(p.Score) OVER (PARTITION BY au.Id ORDER BY p.CreationDate) AS PrevQuestionScore,
        AVG(p.Score) OVER (PARTITION BY au.Id ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RecentAvgScore,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN ActiveUsers au ON p.OwnerUserId = au.Id
    LEFT JOIN Posts accepted ON p.AcceptedAnswerId = accepted.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
      AND p.Score > 0
),
EngagedQuestions AS (
    SELECT 
        qm.PostId,
        qm.Title,
        qm.CreationDate,
        qm.Score,
        qm.ViewCount,
        qm.AnswerCount,
        qm.FavoriteCount,
        qm.CommentCount,
        qm.OwnerId,
        qm.ReputationRank,
        qm.AcceptedScore,
        qm.PrevQuestionScore,
        qm.RecentAvgScore,
        qm.PostStatus,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCountActual,
        SUM(CASE WHEN vl.VoteTypeId IN (2,1) THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vl.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        STRING_AGG(DISTINCT CAST(pl.RelatedPostId AS varchar), ', ') AS LinkedPosts
    FROM QuestionMetrics qm
    LEFT JOIN Votes v ON qm.PostId = v.PostId 
                      AND v.CreationDate BETWEEN qm.CreationDate AND qm.CreationDate + INTERVAL '30 days'
    LEFT JOIN Comments c ON qm.PostId = c.PostId AND c.Score >= 0
    LEFT JOIN PostLinks pl ON qm.PostId = pl.PostId AND pl.LinkTypeId = 1
    LEFT JOIN Votes vl ON qm.PostId = vl.PostId 
                      AND vl.VoteTypeId IN (1,2,3)
                      AND vl.CreationDate <= qm.CreationDate + INTERVAL '7 days'
    GROUP BY qm.PostId, qm.Title, qm.CreationDate, qm.Score, qm.ViewCount, 
             qm.AnswerCount, qm.FavoriteCount, qm.CommentCount, qm.OwnerId, 
             qm.ReputationRank, qm.AcceptedScore, qm.PrevQuestionScore, 
             qm.RecentAvgScore, qm.PostStatus
    HAVING COUNT(DISTINCT v.Id) > 5 OR qm.ViewCount > 1000
),
HighImpactPosts AS (
    SELECT 
        eq.PostId,
        eq.Title,
        eq.CreationDate,
        eq.Score,
        eq.ViewCount,
        eq.AnswerCount,
        eq.FavoriteCount,
        eq.CommentCount,
        eq.OwnerId,
        eq.ReputationRank,
        eq.AcceptedScore,
        eq.PrevQuestionScore,
        eq.RecentAvgScore,
        eq.PostStatus,
        eq.VoteCount,
        eq.CommentCountActual,
        eq.UpVotes,
        eq.DownVotes,
        eq.LinkedPosts,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        CASE 
            WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 'Edited'
            WHEN ph.PostHistoryTypeId IN (10,11) THEN 
                CASE 
                    WHEN (CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS integer) ELSE NULL END) = 101 THEN 'Duplicate Closed'
                    WHEN (CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS integer) ELSE NULL END) = 102 THEN 'Off-topic Closed'
                    ELSE 'Other Close'
                END
            WHEN ph.PostHistoryTypeId = 12 THEN 'Deleted'
            ELSE 'Other'
        END AS HistoryAction,
        ROW_NUMBER() OVER (PARTITION BY eq.OwnerId, eq.PostStatus 
                          ORDER BY eq.ViewCount DESC, eq.VoteCount DESC) AS ImpactRank
    FROM EngagedQuestions eq
    LEFT JOIN PostHistory ph ON eq.PostId = ph.PostId 
                            AND ph.CreationDate > eq.CreationDate 
                            AND ph.CreationDate <= eq.CreationDate + INTERVAL '90 days'
    WHERE (eq.UpVotes - COALESCE(eq.DownVotes, 0)) > 10
       OR eq.AcceptedScore > 5
),
Aggregated AS (
    SELECT 
        hip.OwnerId,
        au.DisplayName AS OwnerName,
        au.Reputation,
        au.ReputationRank,
        COUNT(hip.PostId) AS TotalQuestions,
        SUM(hip.ViewCount) AS TotalViews,
        SUM(hip.VoteCount) AS TotalVotes,
        AVG(hip.RecentAvgScore) AS AvgQuestionQuality,
        SUM(CASE WHEN hip.ImpactRank = 1 THEN 1 ELSE 0 END) AS TopPostsCount,
        STRING_AGG(
            DISTINCT COALESCE(
                SUBSTRING(hip.Title FROM 1 FOR 50) || 
                CASE 
                    WHEN hip.PostStatus = 'Closed' AND hip.HistoryAction LIKE '%Closed%' 
                    THEN ' [CLOSED: ' || hip.HistoryAction || ']'
                    WHEN hip.PostStatus = 'Closed' 
                    THEN ' [CLOSED]'
                    ELSE ''
                END, 
                'Untitled'
            ), 
            ' | '
        ) AS QuestionTitles,
        MAX(hip.HistoryDate) AS LatestActivity,
        SUM(CASE WHEN hip.HistoryAction LIKE '%Closed%' THEN 1 ELSE 0 END) AS ClosedCount,
        SUM(CASE WHEN hip.HistoryAction = 'Edited' THEN 1 ELSE 0 END) AS EditedCount
    FROM HighImpactPosts hip
    INNER JOIN ActiveUsers au ON hip.OwnerId = au.Id
    WHERE hip.PostStatus != 'Community Owned'
      AND (hip.ImpactRank <= 3 OR hip.ViewCount > 5000)
      AND NOT EXISTS (
          SELECT 1 
          FROM Badges b 
          WHERE b.UserId = hip.OwnerId 
            AND b.Name LIKE '%Troll%' 
            AND b.Date >= hip.CreationDate - INTERVAL '1 year'
      )
    GROUP BY hip.OwnerId, au.DisplayName, au.Reputation, au.ReputationRank
    HAVING COUNT(hip.PostId) >= 2 
       AND AVG(hip.RecentAvgScore) > 2
       AND SUM(hip.ViewCount) > 10000
)
SELECT 
    a.OwnerId,
    a.OwnerName,
    a.Reputation,
    a.ReputationRank,
    a.TotalQuestions,
    a.TotalViews,
    a.TotalVotes,
    a.AvgQuestionQuality,
    a.TopPostsCount,
    a.QuestionTitles,
    a.LatestActivity,
    CASE 
        WHEN a.ClosedCount > 0 THEN 'Has Closed Questions'
        WHEN a.EditedCount > a.TotalQuestions * 0.5 THEN 'Frequently Edited'
        ELSE 'Stable Poster'
    END AS EngagementPattern
FROM Aggregated a
ORDER BY a.TotalViews DESC, a.ReputationRank ASC
LIMIT 50;