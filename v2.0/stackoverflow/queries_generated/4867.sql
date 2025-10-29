-- {"query": "4867.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1157} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(u.Reputation) AS MaxReputation,
        AVG(u.Views) AS AvgUserViews,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id ELSE NULL END) AS TotalUpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id ELSE NULL END) AS TotalDownvotesReceived,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        pt.Name AS PostType,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.LastActivityDate,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        STRFTIME('%Y-%m', p.CreationDate) AS PostYearMonth,
        CASE
            WHEN p.Tags IS NULL THEN 'NoTags'
            WHEN p.Tags LIKE '%<sql>%' THEN 'SQLRelated'
            ELSE 'Other'
        END AS TagCategory
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
)
SELECT
    pd.PostId,
    pd.Title,
    pd.PostType,
    pd.PostStatus,
    pd.PostYearMonth,
    pd.TagCategory,
    pd.Score,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.PostViewCount,
    pd.OwnerDisplayName,
    ua.DisplayName AS EditorDisplayName,
    ua.Reputation AS EditorReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    pdr.EditDate AS LastEditBySpecificUser,
    CASE
        WHEN pd.Score > 100 THEN 'HighScore'
        WHEN pd.Score BETWEEN 10 AND 100 THEN 'MediumScore'
        ELSE 'LowScore'
    END AS ScoreBand,
    CAST(pd.AnswerCount AS REAL) / NULLIF(pd.CommentCount, 0) AS AnswerToCommentRatio,
    DATE('now') - pd.CreationDate AS DaysSinceCreation,
    CASE
        WHEN UPPER(pd.Title) LIKE '%SQL%' OR UPPER(pd.Title) LIKE '%DATABASE%' THEN 'Technical'
        ELSE 'General'
    END AS TitleSubjectivity,
    COALESCE(pdr.PostHistoryTypeId, 0) AS LastEditType,
    CASE
        WHEN ua.AvgUserViews IS NULL THEN 0
        ELSE ua.AvgUserViews
    END AS AvgUserViewsForEditor,
    IIF(ua.TotalUpvotesReceived > ua.TotalDownvotesReceived, 'PositiveNet', 'NeutralOrNegativeNet') AS UserVoteNet,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pd.PostId AND c.Score < 0) AS NegativeScoreComments
FROM PostDetails pd
LEFT JOIN RankedPostEdits pdr ON pd.PostId = pdr.PostId AND pdr.rn = 1
LEFT JOIN UserActivity ua ON pdr.UserId = ua.UserId
WHERE pd.PostYearMonth BETWEEN '2023-01' AND '2023-12'
ORDER BY pd.PostYearMonth, pd.Score DESC
LIMIT 1000;