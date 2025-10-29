WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount AS PostFavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS AvgScoreForType,
        LAG(p.CreationDate, 1, p.CreationDate) OVER (ORDER BY p.CreationDate) AS PreviousPostCreationDate,
        LEAD(p.CreationDate, 1, p.CreationDate) OVER (ORDER BY p.CreationDate) AS NextPostCreationDate,
        COUNT(c.Id) FILTER (WHERE c.Id IS NOT NULL) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE v.Id IS NOT NULL) OVER (PARTITION BY p.Id) AS UpVoteCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FILTER (WHERE v.Id IS NOT NULL) OVER (PARTITION BY p.Id) AS DownVoteCountForPost
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN rp.PostTypeId = 1 THEN rp.PostId END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN rp.PostTypeId = 2 THEN rp.PostId END) AS AnswerCount,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN rp.PostScore ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN rp.PostScore ELSE 0 END) AS TotalAnswerScore,
        AVG(rp.PostScore) AS AvgPostScoreForUser,
        MAX(rp.PostCreationDate) AS LastPostDateForUser,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        CASE WHEN COALESCE(u.Views,0) > 0 THEN CAST(COALESCE(u.UpVotes,0) AS DOUBLE PRECISION) / u.Views ELSE 0 END AS UpvoteRatio,
        CASE WHEN COALESCE(u.Views,0) > 0 THEN CAST(COALESCE(u.DownVotes,0) AS DOUBLE PRECISION) / u.Views ELSE 0 END AS DownvoteRatio
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.PostFavoriteCount,
    rp.CommentCountForPost,
    rp.UpVoteCountForPost,
    rp.DownVoteCountForPost,
    upa.UserId,
    upa.DisplayName AS OwnerDisplayName,
    upa.Reputation AS OwnerReputation,
    upa.UserCreationDate AS OwnerCreationDate,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.TotalQuestionScore,
    upa.TotalAnswerScore,
    upa.AvgPostScoreForUser,
    upa.LastPostDateForUser,
    upa.TotalPosts,
    upa.UpvoteRatio,
    upa.DownvoteRatio,
    rp.AvgScoreForType,
    rp.ScoreRank,
    CASE
        WHEN rp.PostScore > rp.AvgScoreForType * 1.5 THEN 'Above Average Performer'
        WHEN rp.PostScore < rp.AvgScoreForType * 0.5 THEN 'Below Average Performer'
        ELSE 'Average Performer'
    END AS PerformanceCategory,
    CASE
        WHEN rp.PostCreationDate < (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') AND rp.PostScore > 0 THEN 'Old High Score Post'
        WHEN rp.PostCreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year') THEN 'Recent Post'
        ELSE 'Established Post'
    END AS AgeCategory,
    COALESCE(upa.DisplayName, 'Anonymous') AS DisplayNameOrAnonymous,
    (rp.PostCreationDate BETWEEN rp.PreviousPostCreationDate AND rp.NextPostCreationDate) AS IsChronologicallyContained,
    (POSITION('Q' IN rp.PostTypeName) > 0) AS IsQuestionType,
    CASE
        WHEN rp.PostFavoriteCount IS NULL THEN '0'
        WHEN rp.PostFavoriteCount > 100 THEN 'Highly Favorited'
        WHEN rp.PostFavoriteCount > 10 THEN 'Moderately Favorited'
        ELSE 'Less Favorited'
    END AS FavoriteStatus,
    (rp.PostScore + rp.CommentCountForPost) AS CombinedScore,
    UPPER(SUBSTRING(COALESCE(upa.DisplayName,'') FROM 1 FOR 1)) AS FirstInitial
FROM RankedPosts rp
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.UserId
WHERE rp.PostScore > 0 OR rp.CommentCountForPost > 0
UNION ALL
SELECT
    NULL, -- PostId
    NULL, -- PostTypeName
    NULL, -- PostCreationDate
    NULL, -- PostScore
    NULL, -- PostViewCount
    NULL, -- PostFavoriteCount
    NULL, -- CommentCountForPost
    NULL, -- UpVoteCountForPost
    NULL, -- DownVoteCountForPost
    NULL, -- UserId
    NULL, -- OwnerDisplayName
    NULL, -- OwnerReputation
    NULL, -- OwnerCreationDate
    NULL, -- QuestionCount
    NULL, -- AnswerCount
    NULL, -- TotalQuestionScore
    NULL, -- TotalAnswerScore
    NULL, -- AvgPostScoreForUser
    NULL, -- LastPostDateForUser
    NULL, -- TotalPosts
    NULL, -- UpvoteRatio
    NULL, -- DownvoteRatio
    NULL, -- AvgScoreForType
    NULL, -- ScoreRank
    NULL, -- PerformanceCategory
    NULL, -- AgeCategory
    NULL, -- DisplayNameOrAnonymous
    NULL, -- IsChronologicallyContained
    NULL, -- IsQuestionType
    NULL, -- FavoriteStatus
    NULL, -- CombinedScore
    NULL -- FirstInitial
WHERE EXISTS (SELECT 1 FROM PostLinks WHERE LinkTypeId = 3);