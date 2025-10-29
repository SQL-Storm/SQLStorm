-- {"query": "4572.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1617} 

WITH PostInteraction AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COUNT(DISTINCT c.Id) AS CommentCountTotal,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn_user_post
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.Id,
        pt.Name,
        p.OwnerUserId,
        u.DisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate
),
RecentPostActivity AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(DISTINCT ph.Id) AS HistoryCount
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (2, 4, 5, 8) -- Body/Title Edits, Rollsbacks
    GROUP BY ph.PostId
),
UserEngagement AS (
    SELECT
        pi.OwnerUserId,
        COUNT(DISTINCT pi.PostId) AS PostsOwned,
        SUM(pi.Score) AS TotalScore,
        AVG(pi.Score) AS AvgScore,
        SUM(pi.ViewCount) AS TotalViews,
        AVG(pi.FavoriteCount) AS AvgFavorites,
        COUNT(DISTINCT CASE WHEN pi.ClosedDate IS NOT NULL THEN pi.PostId ELSE NULL END) AS ClosedPosts,
        SUM(CASE WHEN pi.rn_user_post <= 5 THEN 1 ELSE 0 END) AS RecentPostsCount
    FROM PostInteraction AS pi
    WHERE pi.OwnerUserId IS NOT NULL AND pi.rn_user_post <= 50 -- Consider only the 50 most recent posts per user for this calculation
    GROUP BY pi.OwnerUserId
),
PostDetails AS (
    SELECT
        pi.PostId,
        pi.PostTypeName,
        pi.OwnerUserId,
        pi.OwnerDisplayName,
        pi.CreationDate,
        pi.Score,
        pi.ViewCount,
        pi.AnswerCount,
        pi.CommentCountTotal,
        pi.UpVoteCount,
        pi.DownVoteCount,
        pi.ClosedDate,
        pi.CommunityOwnedDate,
        rpa.LastEditDate,
        rpa.HistoryCount,
        ue.PostsOwned,
        ue.TotalScore,
        ue.AvgScore,
        ue.TotalViews,
        ue.AvgFavorites,
        ue.ClosedPosts,
        ue.RecentPostsCount,
        CASE
            WHEN pi.Score > 100 AND pi.AnswerCount > 10 THEN 'Highly Engaged Question'
            WHEN pi.Score < 0 THEN 'Controversial Post'
            WHEN pi.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN pi.ClosedDate IS NOT NULL THEN 'Closed Post'
            ELSE 'Standard Post'
        END AS PostStatusCategory,
        LOWER(COALESCE(u.Location, 'Unknown')) AS UserLocation,
        DATEDIFF(day, u.CreationDate, GETDATE()) AS UserAgeInDays,
        CASE
            WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
            ELSE 'No Website'
        END AS UserWebsiteStatus,
        SUBSTRING(u.AboutMe, 1, 50) AS AboutMeSnippet -- First 50 characters of AboutMe
    FROM PostInteraction AS pi
    LEFT JOIN RecentPostActivity AS rpa ON pi.PostId = rpa.PostId
    LEFT JOIN UserEngagement AS ue ON pi.OwnerUserId = ue.OwnerUserId
    LEFT JOIN Users AS u ON pi.OwnerUserId = u.Id
    WHERE pi.PostTypeName = 'Question' -- Focusing on questions for this analysis
)
SELECT
    pd.PostId,
    pd.PostTypeName,
    pd.OwnerUserId,
    pd.OwnerDisplayName,
    pd.CreationDate,
    pd.Score,
    pd.ViewCount,
    pd.AnswerCount,
    pd.CommentCountTotal,
    pd.UpVoteCount,
    pd.DownVoteCount,
    pd.ClosedDate,
    pd.CommunityOwnedDate,
    pd.LastEditDate,
    pd.HistoryCount,
    pd.PostsOwned,
    pd.TotalScore,
    pd.AvgScore,
    pd.TotalViews,
    pd.AvgFavorites,
    pd.ClosedPosts,
    pd.RecentPostsCount,
    pd.PostStatusCategory,
    pd.UserLocation,
    pd.UserAgeInDays,
    pd.UserWebsiteStatus,
    pd.AboutMeSnippet,
    CASE
        WHEN pd.AvgScore IS NOT NULL AND pd.AvgScore > 5 THEN 'High Performer'
        WHEN pd.ClosedPosts > 0 AND pd.PostsOwned > 10 THEN 'Experienced but has Closed Content'
        WHEN pd.HistoryCount > 5 THEN 'Frequently Edited'
        ELSE 'Standard Performer'
    END AS PerformanceTier,
    CONCAT(
        'User ',
        pd.OwnerDisplayName,
        ' created a ',
        pd.PostTypeName,
        ' on ',
        FORMAT(pd.CreationDate, 'yyyy-MM-dd'),
        ' with a score of ',
        pd.Score,
        '. It has ',
        pd.AnswerCount,
        ' answers and ',
        pd.CommentCountTotal,
        ' comments. User has ',
        pd.PostsOwned,
        ' posts owned, with an average score of ',
        CAST(pd.AvgScore AS VARCHAR(10)),
        '.'
    ) AS DescriptiveSummary
FROM PostDetails AS pd
WHERE pd.OwnerUserId IS NOT NULL
  AND pd.CreationDate >= DATEADD(year, -1, GETDATE()) -- Posts from the last year
  AND pd.UserAgeInDays > 365 -- Users created more than a year ago
ORDER BY pd.Score DESC, pd.CreationDate DESC
LIMIT 1000;
