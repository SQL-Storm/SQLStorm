WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score END) AS AvgPostScore,
        MAX(p.Score) AS MaxPostScore,
        STRING_AGG(DISTINCT TRIM(BOTH ' ' FROM REGEXP_REPLACE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '\\s+', ' ', 'g')), ', ') AS UserTags,
        EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS AccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
),
BadgeAnalysis AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN TagBased = '1' THEN Name END) AS UniqueTagBadges,
        MIN(Date) AS FirstBadgeDate,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
QuestionPerformance AS (
    SELECT 
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community'
            ELSE 'Open'
        END AS Status,
        LENGTH(q.Body) - LENGTH(REPLACE(LOWER(q.Body), '<code>', '')) AS CodeBlockCount,
        COALESCE(
            (SELECT STRING_AGG(c.Text, ' | ' ORDER BY c.Score DESC)
             FROM Comments c 
             WHERE c.PostId = q.Id 
               AND c.Score > 5
             LIMIT 3), 
            'No popular comments'
        ) AS TopComments,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) AS UserQuestionRank,
        PERCENT_RANK() OVER (ORDER BY q.ViewCount) AS ViewPercentile,
        LAG(q.CreationDate) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS PrevQuestionDate,
        LEAD(q.Score, 1, 0) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS NextQuestionScore
    FROM Posts q
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
),
AnswerAnalysis AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS BestAnswerScore,
        MIN(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600) AS FastestAnswerHours,
        COUNT(DISTINCT a.OwnerUserId) AS UniqueAnswerers,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAccepted
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2
        AND q.PostTypeId = 1
    GROUP BY a.ParentId
),
VotePatterns AS (
    SELECT 
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(CASE WHEN VoteTypeId = 8 THEN 1 END) AS BountyStarts,
        SUM(CASE WHEN VoteTypeId = 8 THEN BountyAmount ELSE 0 END) AS TotalBounty,
        STDDEV(EXTRACT(EPOCH FROM CreationDate)) AS VoteTimeVariance
    FROM Votes
    WHERE CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'
    GROUP BY PostId
),
EditHistory AS (
    SELECT 
        PostId,
        COUNT(*) AS EditCount,
        COUNT(DISTINCT UserId) AS UniqueEditors,
        MAX(CASE WHEN PostHistoryTypeId IN (7,8,9) THEN 1 ELSE 0 END) AS HasRollback,
        STRING_AGG(
            CASE 
                WHEN PostHistoryTypeId = 10 THEN 'Closed:' || COALESCE(Comment, 'N/A')
                WHEN PostHistoryTypeId = 11 THEN 'Reopened'
                ELSE NULL
            END, ' -> ' ORDER BY CreationDate
        ) AS CloseReopenHistory
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4,5,6,7,8,9,10,11)
    GROUP BY PostId
)
SELECT 
    um.DisplayName,
    um.Reputation,
    UPPER(SUBSTRING(um.Location FROM 1 FOR 30)) AS LocationShort,
    um.QuestionCount,
    um.AnswerCount,
    ROUND(um.AvgPostScore, 2) AS AvgPostScore,
    COALESCE(ba.GoldBadges, 0) + COALESCE(ba.SilverBadges, 0) * 0.5 + COALESCE(ba.BronzeBadges, 0) * 0.25 AS BadgeScore,
    qp.QuestionId,
    qp.QuestionScore,
    CASE 
        WHEN qp.ViewCount IS NULL THEN 'No views'
        WHEN qp.ViewCount < 100 THEN 'Low'
        WHEN qp.ViewCount < 1000 THEN 'Medium'
        WHEN qp.ViewCount < 10000 THEN 'High'
        ELSE 'Viral'
    END AS ViewCategory,
    qp.Status,
    COALESCE(qp.CodeBlockCount, 0) AS CodeBlocks,
    SUBSTRING(qp.TopComments FROM 1 FOR 100) AS CommentPreview,
    CAST(qp.ViewPercentile * 100 AS DECIMAL(10,2)) AS ViewPercentile,
    COALESCE(aa.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(aa.FastestAnswerHours, -1) AS FastestAnswerHours,
    COALESCE(vp.Upvotes, 0) - COALESCE(vp.Downvotes, 0) AS NetVotes,
    COALESCE(vp.TotalBounty, 0) AS TotalBounty,
    COALESCE(eh.EditCount, 0) AS EditCount,
    CASE 
        WHEN eh.HasRollback = 1 THEN 'Yes' 
        ELSE 'No' 
    END AS HadRollback,
    COALESCE(eh.CloseReopenHistory, 'Never closed') AS CloseHistory,
    DENSE_RANK() OVER (
        ORDER BY 
            um.Reputation DESC, 
            COALESCE(ba.GoldBadges, 0) DESC,
            um.AvgPostScore DESC NULLS LAST
    ) AS UserRank
FROM UserMetrics um
LEFT JOIN BadgeAnalysis ba ON um.Id = ba.UserId
LEFT JOIN QuestionPerformance qp ON um.Id = qp.OwnerUserId
LEFT JOIN AnswerAnalysis aa ON qp.QuestionId = aa.QuestionId
LEFT JOIN VotePatterns vp ON qp.QuestionId = vp.PostId
LEFT JOIN EditHistory eh ON qp.QuestionId = eh.PostId
WHERE um.PostCount > 0
    AND (qp.UserQuestionRank <= 5 OR qp.UserQuestionRank IS NULL)
    AND NOT EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.PostId = qp.QuestionId 
            AND ph.PostHistoryTypeId = 12
    )
    AND um.Reputation > (
        SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Reputation)
        FROM Users
        WHERE CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
    )
ORDER BY 
    UserRank,
    qp.QuestionScore DESC NULLS LAST,
    qp.ViewCount DESC NULLS LAST
LIMIT 500;